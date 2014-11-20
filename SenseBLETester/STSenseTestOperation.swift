//
//  STTestOperation.swift
//  SenseBLETester
//
//  Created by Jimmy Lu on 11/17/14.
//  Copyright (c) 2014 Hello, Inc. All rights reserved.
//

import Foundation

class STSenseTestOperation : NSOperation {
    
    private var _executing : Bool
    private var _finished : Bool
    private var _failureCode : Int

    let senseManager : SENSenseManager
    
    init(senseManager : SENSenseManager) {
        self.senseManager = senseManager
        self._failureCode = 0
        self._executing = false
        self._finished = false
    }
    
    override var executing : Bool {
        get { return self._executing }
        set {
            willChangeValueForKey("isExecuting")
            self._executing = newValue
            didChangeValueForKey("isExecuting")
        }
    }
    
    override var finished : Bool {
        get { return self._finished }
        set {
            willChangeValueForKey("isFinished")
            self._finished = newValue
            didChangeValueForKey("isFinished")
        }
    }
    
    override func main() {
        if (self.cancelled) {
            return
        }
        
        dispatch_async(dispatch_get_main_queue(), { () -> Void in
            self.execute()
        });
        
    }
    
    func execute() {
        self.executing = true
    }
    
    func done(error: NSError?) {
        if (self.cancelled) {
            return
        }
        
        self.executing = false
        if (error != nil) {
            self._failureCode = error!.code
        }
        self.finished = true
    }
    
    func getErrorCode() -> Int {
        return self._failureCode;
    }
}
