// Copyright (c) 2021 WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 Inc. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/test;
import ballerina/log;
import ballerina/random;
import ballerina/lang.'float;
import ballerina/os;

configurable string accessKeyId = os:getEnv("ACCESS_KEY_ID");
configurable string secretAccessKey = os:getEnv("SECRET_ACCESS_KEY");
configurable string region = os:getEnv("REGION");

ConnectionConfig configuration = {
    accessKey: accessKeyId,
    secretKey: secretAccessKey,
    region: region
};

Client sqs = check new (configuration);
string fifoQueueResourcePath = "";
string standardQueueResourcePath = "";
string receivedReceiptHandler = "";
string standardQueueReceivedReceiptHandler = "";

@test:Config {
    groups: ["group1"]
}
function testCreateFIFOQueue() {
    QueueAttributes queueAttributes = {  
        visibilityTimeout : 400,
        fifoQueue : true
    };
    map<string> tags = {};
    tags["QueueType"] = "Production";
    CreateQueueResponse|error response = sqs->createQueue(genRandQueueName(true), queueAttributes, tags);
    if (response is CreateQueueResponse) {
        string queueResponse = response.createQueueResult.queueUrl;
        if (queueResponse.startsWith("https://sqs.")) {
            string|error queueResourcePathAny = splitString(queueResponse, AMAZON_HOST, 1);
            if (queueResourcePathAny is string) {
                fifoQueueResourcePath = queueResourcePathAny;
                log:printInfo("SQS queue was created. Queue URL: " + queueResponse);
                test:assertTrue(true);
            } else {
                log:printInfo("Queue URL is not Amazon!");
                test:assertTrue(false);
            }
        } else {
            log:printInfo("Error while creating the queue.");
            test:assertTrue(false);
        }
    } else {
        log:printInfo("Error while creating the queue.");
        test:assertTrue(false);
    }
}

@test:Config {
    groups: ["group2"]
}
function testCreateStandardQueue() {
    CreateQueueResponse|error response = sqs->createQueue(genRandQueueName(false));
    if (response is CreateQueueResponse) {
        string queueResponse = response.createQueueResult.queueUrl;
        if (queueResponse.startsWith("https://sqs.")) {
            string|error queueResourcePathAny = splitString(queueResponse, AMAZON_HOST, 1);
            if (queueResourcePathAny is string) {
                standardQueueResourcePath = queueResourcePathAny;
                log:printInfo("SQS queue was created. Queue URL: " + queueResponse);
                test:assertTrue(true);
            } else {
                log:printInfo("Queue URL is not Amazon!");
                test:assertTrue(false);
            }
        } else {
            log:printInfo("Error while creating the queue.");
            test:assertTrue(false);
        }
    } else {
        log:printInfo("Error while creating the queue.");
        test:assertTrue(false);
    }
}

@test:Config {
    dependsOn: [testCreateFIFOQueue],
    groups: ["group1"]
}
function testSendMessage() {
    MessageAttribute[] messageAttributes = 
        [{keyName : "N1", value : { stringValue : "V1", dataType : "String"}},
        {keyName : "N2", value : { stringValue : "V2", dataType : "String"}}];
    SendMessageResponse|error response = sqs->sendMessage("New Message Text", fifoQueueResourcePath,
        messageAttributes, "grpID1", "dupID1");
    if (response is SendMessageResponse) {
        if (response.sendMessageResult.messageId != "") {
            log:printInfo("Sent message to SQS. MessageID: " + response.sendMessageResult.messageId);
            test:assertTrue(true);
        } else {
            log:printInfo("Error while sending the message to the queue.");
            test:assertTrue(false);
        }
    } else {
        log:printInfo("Error while sending the message to the queue.");
        test:assertTrue(false);
    }
}

@test:Config {
    dependsOn: [testSendMessage],
    groups: ["group1"]
}
function testReceiveMessage() {
    string[] attributeNames = ["SenderId"];
    string[] messageAttributeNames = ["N1", "N2"];
    ReceiveMessageResponse|error response = sqs->receiveMessage(fifoQueueResourcePath, 1, 600, 2, attributeNames, messageAttributeNames);
    if (response is ReceiveMessageResponse) {
        if ((response.receiveMessageResult.message)[0].receiptHandle != "") {
            receivedReceiptHandler = <@untainted>(response.receiveMessageResult.message)[0].receiptHandle;
            log:printInfo("Successfully received the message. Receipt Handle: " + (response.receiveMessageResult.message)[0].receiptHandle);
            test:assertTrue(true);
        } else {
            log:printInfo("Error occurred while receiving the message.");
            test:assertTrue(false);
        }
    } else {
        log:printInfo("Error occurred while receiving the message.");
        test:assertTrue(false);
    }
}

@test:Config {
    dependsOn: [testReceiveMessage],
    groups: ["group1"]
}
function testDeleteMessage() {
    string receiptHandler = receivedReceiptHandler;
    DeleteMessageResponse|error response = sqs->deleteMessage(fifoQueueResourcePath, receiptHandler);
    if (response is DeleteMessageResponse) {
        log:printInfo("Successfully deleted the message from the queue.");
        test:assertTrue(true);
    } else {
        log:printInfo("Error occurred while deleting the message.");
        test:assertTrue(false);
    }
}

@test:Config {
    dependsOn: [testCreateStandardQueue],
    groups: ["group2"]
}
function testCRUDOperationsForMultipleMessages() {
    log:printInfo("Test, testCRUDOperationsForMultipleMessages is started ...");
    int msgCnt = 0;

    // Send 2 messages to the queue
    while (msgCnt < 2) {
        log:printInfo("standardQueueResourcePath " + standardQueueResourcePath);
        SendMessageResponse|error response1 = sqs->sendMessage("There is a tree", standardQueueResourcePath);
        if (response1 is SendMessageResponse) {
            log:printInfo("Sent an alert to the queue. MessageID: " + response1.sendMessageResult.messageId);
        } else {
            log:printError("Error occurred while trying to send an alert to the SQS queue!");
            test:assertTrue(false);
        }
        msgCnt = msgCnt + 1;
    }

    // Receive and delete the 2 messages from the queue
    msgCnt = 0;
    int processesMsgCnt = 0;
    while(msgCnt < 2) {
        ReceiveMessageResponse|error response2 = sqs->receiveMessage(standardQueueResourcePath, 10, 2, 1);
        if (response2 is ReceiveMessageResponse) {
            if ((response2.receiveMessageResult.message).length() > 0) {
                foreach var eachResponse in (response2.receiveMessageResult.message) {
                    standardQueueReceivedReceiptHandler = <@untainted>eachResponse.receiptHandle;
                    DeleteMessageResponse|error deleteResponse = sqs->deleteMessage(standardQueueResourcePath, standardQueueReceivedReceiptHandler);
                    if (deleteResponse is DeleteMessageResponse) {
                        processesMsgCnt = processesMsgCnt + 1;
                        log:printInfo("Deleted the fire alert \"" + eachResponse.body + "\" from the queue.");
                    } else {
                        log:printError("Error occurred while deleting a message.");
                        test:assertTrue(false);
                    }
                }
            } else {
                log:printInfo("Queue is empty. No messages to be deleted.");
            }
        } else {
            log:printError("Error occurred while receiving a message.");
            test:assertTrue(false);
        }
        msgCnt = msgCnt + 1;
    }
    if (processesMsgCnt == 2) {
        log:printInfo("Successfully deleted all the messages from the queue!");
        test:assertTrue(true);
    } else {
        log:printInfo("Error occurred while processing the messages.");
        test:assertTrue(false);
    }
}

@test:AfterSuite {}
function testDeleteStandardQueue() {
    DeleteQueueResponse|error response = sqs->deleteQueue(standardQueueResourcePath);
    if (response is DeleteQueueResponse) {
        log:printInfo("Successfully deleted the queue.");
        test:assertTrue(true);
    } else {
        log:printInfo("Error occurred while deleting the queue.");
        test:assertTrue(false);
    }
}

@test:AfterSuite {}
function testDeleteFIFOQueue() {
    DeleteQueueResponse|error response = sqs->deleteQueue(fifoQueueResourcePath);
    if (response is DeleteQueueResponse) {
        log:printInfo("Successfully deleted the queue.");
        test:assertTrue(true);
    } else {
        log:printInfo("Error occurred while deleting the queue.");
        test:assertTrue(false);
    }
}

isolated function genRandQueueName(boolean isFifo = false) returns string {
    float ranNumFloat = random:createDecimal()*10000000.0;
    anydata ranNumInt = <int> float:round(ranNumFloat);
    string queueName = "testQueue" + ranNumInt.toString();
    if (isFifo) {
        return queueName + ".fifo";
    } else {
        return queueName;
    }
}
