//
//  STSenseTestSuite.swift
//  SenseBLETester
//
//  Created by Jimmy Lu on 11/18/14.
//  Copyright (c) 2014 Hello, Inc. All rights reserved.
//

import Foundation

enum SenseTestType : String {
    case GetWiFi = "Get WiFi",
         ScanWiFi = "Scan WiFi",
         SetWiFi = "Set WiFi (Hello)",
         EnablePairingMode = "Enable Pairing Mode"
}

class STSenseTestSuite : NSObject {
    
    let testQueue = NSOperationQueue()
    let testResults = NSMutableDictionary()
    let senseManager : SENSenseManager
    var disconnectObserver : String?
    var done : Bool
    var success : Bool
    var onUpdate : (() -> Void)?
    var onDone : (() -> Void)?
    
    init(senseManager : SENSenseManager) {
        self.senseManager = senseManager
        self.testQueue.maxConcurrentOperationCount = 1 // serial
        self.testQueue.suspended = true
        self.done = false
        self.success = true
    }
    
    private func addOperation(operation : STSenseTestOperation, type : SenseTestType) {
        operation.completionBlock = {
            let code = operation.getErrorCode()
            self.testResults[type.rawValue] = code
            self.done = self.testQueue.operationCount == 0
            self.success &= code == 0
            
            dispatch_async(dispatch_get_main_queue(), {
                if (self.done) {
                    self.senseManager.removeUnexpectedDisconnectObserver(self.disconnectObserver?)
                    self.senseManager.disconnectFromSense()
                    self.onDone?()
                } else {
                    self.onUpdate?()
                }
            })
        }
        self.testQueue.addOperation(operation)
    }
    
    func testResultCodeFor(type : SenseTestType) -> Int {
        return self.testResults.valueForKey(type.rawValue) as Int
    }
    
    func testsInSuite() -> [SenseTestType] {
        return [SenseTestType.GetWiFi,
                SenseTestType.ScanWiFi,
                SenseTestType.SetWiFi,
                SenseTestType.EnablePairingMode];
    }
    
    func start() {
        self.disconnectObserver = self.senseManager.observeUnexpectedDisconnect {[weak self] (error: NSError!) -> Void in
            if self? == nil {return}
            for operation in self!.testQueue.operations as [STSenseTestOperation] {
                operation.cancel()
                
            }
            self?.success = false
            self!.onDone?()
        }
        self.done = false
        self.testQueue.suspended = true
        self.addOperation(STSenseGetWiFi(senseManager: self.senseManager), type : SenseTestType.GetWiFi)
        self.addOperation(STSenseScanWiFi(senseManager: self.senseManager), type : SenseTestType.ScanWiFi)
        self.addOperation(STSenseSetWiFi(senseManager: self.senseManager), type : SenseTestType.SetWiFi)
        self.addOperation(STSensePairngMode(senseManager : self.senseManager), type : SenseTestType.EnablePairingMode)
        self.testQueue.suspended = false
    }
    
}
