/********************************************************************************
 *    Copyright (C) 2014 GSI Helmholtzzentrum fuer Schwerionenforschung GmbH    *
 *                                                                              *
 *              This software is distributed under the terms of the             *
 *         GNU Lesser General Public Licence version 3 (LGPL) version 3,        *
 *                  copied verbatim in the file "LICENSE"                       *
 ********************************************************************************/
/**
 * runTestReq.cxx
 *
 * @since 2015-09-05
 * @author A. Rybalchenko
 */

#include "FairMQLogger.h"
#include "FairMQTestReq.h"

#include <iostream>
#include <chrono>
#include <thread>

int main(int argc, char** argv)
{
    reinit_logger(false);
    SET_LOG_CONSOLE_LEVEL(WARN);

    FairMQTestReq testReq;
    testReq.CatchSignals();

    std::string transport;
    if ( (argc != 2) || (argv[1] == NULL) )
    {
        LOG(ERROR) << "Transport for the test not specified!";
        return 1;
    }

    if ( strncmp(argv[1],"zeromq",6) == 0 )
    {
        transport = "zeromq";
        testReq.SetTransport(transport);
    }
    else if ( strncmp(argv[1],"nanomsg",7) == 0 )
    {
        transport = "nanomsg";
        testReq.SetTransport(transport);
    }
    else
    {
        LOG(ERROR) << "Incorrect transport requested! Expected 'zeromq' or 'nanomsg', found: " << argv[1];
        return 1;
    }

    testReq.SetProperty(FairMQTestReq::Id, "testReq" + std::to_string(getpid()));

    FairMQChannel reqChannel("req", "connect", "tcp://127.0.0.1:5558");
    if (transport == "nanomsg")
    {
        reqChannel.UpdateAddress("tcp://127.0.0.1:5758");
    }
    reqChannel.UpdateRateLogging(0);
    testReq.fChannels["data"].push_back(reqChannel);

    testReq.ChangeState("INIT_DEVICE");
    testReq.WaitForEndOfState("INIT_DEVICE");

    testReq.ChangeState("INIT_TASK");
    testReq.WaitForEndOfState("INIT_TASK");

    testReq.ChangeState("RUN");
    testReq.WaitForEndOfState("RUN");

    // nanomsg does not implement the LINGER option. Give the sockets some time before their queues are terminated
    if (transport == "nanomsg")
    {
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }

    testReq.ChangeState("RESET_TASK");
    testReq.WaitForEndOfState("RESET_TASK");

    testReq.ChangeState("RESET_DEVICE");
    testReq.WaitForEndOfState("RESET_DEVICE");

    testReq.ChangeState("END");

    return 0;
}
