//
//  STSenseGetWiFi.swift
//  SenseBLETester
//
//  Created by Jimmy Lu on 11/17/14.
//  Copyright (c) 2014 Hello, Inc. All rights reserved.
//

import Foundation

class STSenseGetWiFi : STSenseTestOperation {
    
    override func execute() {
        super.execute()
        self.senseManager.getConfiguredWiFi({ (ssid: String!, state : SENWiFiConnectionState) -> () in
            self.done(nil)
        }, failure: { (error: NSError!) -> () in
            self.done(error)
        });
    }
    
}
