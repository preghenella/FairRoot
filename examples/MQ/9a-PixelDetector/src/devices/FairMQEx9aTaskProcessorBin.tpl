/********************************************************************************
 *    Copyright (C) 2014 GSI Helmholtzzentrum fuer Schwerionenforschung GmbH    *
 *                                                                              *
 *              This software is distributed under the terms of the             * 
 *         GNU Lesser General Public Licence version 3 (LGPL) version 3,        *  
 *                  copied verbatim in the file "LICENSE"                       *
 ********************************************************************************/

// special class to expose protected TMessage constructor
class Ex9TMessage2 : public TMessage
{
  public:
  Ex9TMessage2(void* buf, Int_t len)
    : TMessage(buf, len)
  {
    ResetBit(kIsOwner);
  }
};

template <typename T>
FairMQEx9aTaskProcessorBin<T>::FairMQEx9aTaskProcessorBin()
  : FairMQDevice()
  , fInputChannelName("data-in")
  , fOutputChannelName("data-out")
  , fParamChannelName("param")
  , fEventHeader(NULL)
  , fNewRunId(1)
  , fCurrentRunId(-1)
  , fDataToKeep("")
  , fReceivedMsgs(0)
  , fSentMsgs(0)
  , fFairTask(NULL)
  , fParCList(NULL)
  , fGeoPar(nullptr)
{
}

template <typename T>
FairMQEx9aTaskProcessorBin<T>::~FairMQEx9aTaskProcessorBin()
{
  LOG(INFO) << "deteling fGeoPar"; 
  delete fGeoPar;
  fGeoPar=nullptr;
  delete fFairTask;
}


template <typename T>
void FairMQEx9aTaskProcessorBin<T>::Init()
{
  fDataToKeep        = fConfig->GetValue<std::string>("keep-data");
  fInputChannelName  = fConfig->GetValue<std::string>("in-channel");
  fOutputChannelName = fConfig->GetValue<std::string>("out-channel");
  fParamChannelName  = fConfig->GetValue<std::string>("par-channel");

    //fHitFinder->InitMQ(fRootParFileName,fAsciiParFileName);
  fFairTask = new T();
  fGeoPar = new FairGeoParSet("FairGeoParSet");
  fParCList = new TList();
  fParCList->Add(fGeoPar);
  fFairTask->GetParList(fParCList);
  
  OnData(fInputChannelName, &FairMQEx9aTaskProcessorBin<T>::ProcessData);
}

template <typename T>
bool FairMQEx9aTaskProcessorBin<T>::ProcessData(FairMQParts& parts, int /*index*/)
{
  // LOG(TRACE)<<"message received with " << parts.Size() << " parts!";
  fReceivedMsgs++;
  
  if ( parts.Size() == 0 ) return 0; // probably impossible, but still check

  // expecting even number of parts in the form: header,data,header,data,header,data and so on...
  int nPPE = 2; // nof parts per event

  if ( parts.Size()%nPPE >= 1 )
    LOG(INFO) << "received " << parts.Size() << " parts, will ignore last part!!!";

  // creating output multipart message
  FairMQParts partsOut;

  for ( int ievent = 0 ; ievent < parts.Size()/nPPE ; ievent++ ) {
    // the first part should be the event header
    PixelPayload::EventHeader* payloadE = static_cast<PixelPayload::EventHeader*>(parts.At(nPPE*ievent)->GetData());
    // LOG(TRACE) << "GOT EVENT " << payloadE->fMCEntryNo << " OF RUN " << payloadE->fRunId << " (part " << payloadE->fPartNo << ")";

    fNewRunId = payloadE->fRunId;
    if(fNewRunId!=fCurrentRunId)
      {
        fCurrentRunId=fNewRunId;
        UpdateParameters();
        fFairTask->InitMQ(fParCList);

        LOG(INFO) << "Parameters updated, back to ProcessData(" << parts.Size() << " parts!)";
      }

    // the second part should the TClonesArray with necessary data... now assuming Digi
    PixelPayload::Digi* payloadD = static_cast<PixelPayload::Digi*>(parts.At(nPPE*ievent+1)->GetData());
    int digiArraySize = parts.At(nPPE*ievent+1)->GetSize();
    int nofDigis      = digiArraySize / sizeof(PixelPayload::Digi);

    // LOG(TRACE) << "    EVENT HAS " << nofDigis << " DIGIS!!!";

    // create eventHeader part
    PixelPayload::EventHeader* header = new PixelPayload::EventHeader();
    header->fRunId     = payloadE->fRunId;
    header->fMCEntryNo = payloadE->fMCEntryNo;
    header->fPartNo    = payloadE->fPartNo;
    FairMQMessagePtr msgHeader(NewMessage(header,
                                          sizeof(PixelPayload::EventHeader),
                                          [](void* data, void* /*hint*/) { delete static_cast<PixelPayload::EventHeader*>(data); }
                                          ));
    partsOut.AddPart(std::move(msgHeader));

    // create part with hits
    int hitsSize = nofDigis*sizeof(PixelPayload::Hit);

    FairMQMessagePtr msgTCA = NewMessage(hitsSize);

    PixelPayload::Hit* hitPayload = static_cast<PixelPayload::Hit*>(msgTCA->GetData());

    // actually find hits
    int nofHits = 0;
    fFairTask->ExecMQ(payloadD,nofDigis,hitPayload,nofHits);

    partsOut.AddPart(std::move(msgTCA));
  }
  
  Send(partsOut, fOutputChannelName);
  fSentMsgs++;

  return true;
}

template <typename T>
void FairMQEx9aTaskProcessorBin<T>::PostRun()
{
    MQLOG(INFO) << "FairMQEx9aTaskProcessorBin<T>::PostRun() Received " << fReceivedMsgs << " and sent " << fSentMsgs << " messages!";
}


template <typename T>
void FairMQEx9aTaskProcessorBin<T>::CustomCleanup(void* /*data*/, void *hint)
{
    delete (std::string*)hint;
}


template <typename T>
void FairMQEx9aTaskProcessorBin<T>::UpdateParameters() {
  for ( int iparC = 0 ; iparC < fParCList->GetEntries() ; iparC++ ) {
    FairParGenericSet* tempObj = (FairParGenericSet*)(fParCList->At(iparC));
    fParCList->Remove(tempObj);
    fParCList->AddAt(UpdateParameter(tempObj),iparC);
  }
}

template <typename T>
FairParGenericSet* FairMQEx9aTaskProcessorBin<T>::UpdateParameter(FairParGenericSet* thisPar) {
  std::string paramName = thisPar->GetName();
  //  boost::this_thread::sleep(boost::posix_time::milliseconds(1000));
  std::string* reqStr = new std::string(paramName + "," + std::to_string(fCurrentRunId));
  LOG(WARN) << "Requesting parameter \"" << paramName << "\" for Run ID " << fCurrentRunId << " (" << thisPar << ")";
  std::unique_ptr<FairMQMessage> req(NewMessage(const_cast<char*>(reqStr->c_str()), reqStr->length(), CustomCleanup, reqStr));
  std::unique_ptr<FairMQMessage> rep(NewMessage());
  
  if (Send(req,fParamChannelName) > 0)
    {
      if (Receive(rep,fParamChannelName) > 0)
	{
	  Ex9TMessage2 tm(rep->GetData(), rep->GetSize());
	  thisPar = (FairParGenericSet*)tm.ReadObject(tm.GetClass());
	  LOG(WARN) << "Received parameter"<< paramName <<" from the server (" << thisPar << ")";
	  return thisPar;
	}
    } 
  return NULL;
}
