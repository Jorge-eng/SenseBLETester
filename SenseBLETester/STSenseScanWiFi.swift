//
//  STSenseScanWiFi.swift
//  SenseBLETester
//
//  Created by Jimmy Lu on 11/17/14.
//  Copyright (c) 2014 Hello, Inc. All rights reserved.
//

import Foundation

class STSenseScanWiFi : STSenseTestOperation {
    
    override func execute() {
        super.execute()
        self.senseManager.scanForWifiNetworks({ (response : AnyObject?) -> Void in
            self.done(nil)
        }, failure: { (error : NSError?) -> Void in
            self.done(error)
        })
        
    }
    
}
