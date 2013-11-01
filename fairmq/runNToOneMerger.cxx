/*
 * runMerger.cxx
 *
 *  Created on: Dec 6, 2012
 *      Author: dklein
 */

#include <iostream>
#include <csignal>

#include "FairMQLogger.h"
#include "FairMQStandaloneMerger.h"


FairMQStandaloneMerger merger;

static void s_signal_handler (int signal)
{
  std::cout << std::endl << "Caught signal " << signal << std::endl;

  merger.ChangeState(FairMQStandaloneMerger::STOP);
  merger.ChangeState(FairMQStandaloneMerger::END);

  std::cout << "Shutdown complete. Bye!" << std::endl;
  exit(1);
}

static void s_catch_signals (void)
{
  struct sigaction action;
  action.sa_handler = s_signal_handler;
  action.sa_flags = 0;
  sigemptyset(&action.sa_mask);
  sigaction(SIGINT, &action, NULL);
  sigaction(SIGTERM, &action, NULL);
}

int main(int argc, char** argv)
{
  if ( argc < 16 || (argc-8)%4!=0 ) {
    std::cout << "Usage: merger \tID numIoTreads numInputs\n"
              << "\t\tinputSocketType inputRcvBufSize inputMethod inputAddress\n"
              << "\t\tinputSocketType inputRcvBufSize inputMethod inputAddress\n"
              << "\t\t...\n"
              << "\t\toutputSocketType outputSndBufSize outputMethod outputAddress\n"
              << argc << std::endl;
    return 1;
  }

  s_catch_signals();

  std::stringstream logmsg;
  logmsg << "PID: " << getpid();
  FairMQLogger::GetInstance()->Log(FairMQLogger::INFO, logmsg.str());

  int i = 1;

  merger.SetProperty(FairMQStandaloneMerger::Id, argv[i]);
  ++i;

  int numIoThreads;
  std::stringstream(argv[i]) >> numIoThreads;
  merger.SetProperty(FairMQStandaloneMerger::NumIoThreads, numIoThreads);
  ++i;

  int numInputs;
  std::stringstream(argv[i]) >> numInputs;
  merger.SetProperty(FairMQStandaloneMerger::NumInputs, numInputs);
  ++i;

  merger.SetProperty(FairMQStandaloneMerger::NumOutputs, 1);


  merger.ChangeState(FairMQStandaloneMerger::INIT);


  int inputSocketType;
  for (int iInput = 0; iInput < numInputs; iInput++ ) {
    inputSocketType = ZMQ_SUB;
    if (strcmp(argv[i], "pull") == 0) {
      inputSocketType = ZMQ_PULL;
    }
    merger.SetProperty(FairMQStandaloneMerger::InputSocketType, inputSocketType, iInput);
    ++i;
    int inputRcvBufSize;
    std::stringstream(argv[i]) >> inputRcvBufSize;
    merger.SetProperty(FairMQStandaloneMerger::InputRcvBufSize, inputRcvBufSize, iInput);
    ++i;
    merger.SetProperty(FairMQStandaloneMerger::InputMethod, argv[i], iInput);
    ++i;
    merger.SetProperty(FairMQStandaloneMerger::InputAddress, argv[i], iInput);
    ++i;
  }

  int outputSocketType = ZMQ_PUB;
  if (strcmp(argv[i], "push") == 0) {
    outputSocketType = ZMQ_PUSH;
  }
  merger.SetProperty(FairMQStandaloneMerger::OutputSocketType, outputSocketType, 0);
  ++i;
  int outputSndBufSize;
  std::stringstream(argv[i]) >> outputSndBufSize;
  merger.SetProperty(FairMQStandaloneMerger::OutputSndBufSize, outputSndBufSize, 0);
  ++i;
  merger.SetProperty(FairMQStandaloneMerger::OutputMethod, argv[i], 0);
  ++i;
  merger.SetProperty(FairMQStandaloneMerger::OutputAddress, argv[i], 0);
  ++i;


  merger.ChangeState(FairMQStandaloneMerger::SETOUTPUT);
  merger.ChangeState(FairMQStandaloneMerger::SETINPUT);
  merger.ChangeState(FairMQStandaloneMerger::RUN);


  char ch;
  std::cin.get(ch);

  merger.ChangeState(FairMQStandaloneMerger::STOP);
  merger.ChangeState(FairMQStandaloneMerger::END);

  return 0;
}

