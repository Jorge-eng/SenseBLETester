//
//  STSensePairngMode.swift
//  SenseBLETester
//
//  Created by Jimmy Lu on 11/20/14.
//  Copyright (c) 2014 Hello, Inc. All rights reserved.
//

import Foundation

class STSensePairngMode: STSenseTestOperation {

    override func execute() {
        super.execute()
        self.senseManager.enablePairingMode(true, success: { (response : AnyObject?) -> Void in
            self.done(nil)
        }, failure: { (error: NSError!) -> Void in
            self.done(error)
        })
    }
    
}
