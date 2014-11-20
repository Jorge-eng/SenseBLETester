//
//  STSenseSetWiFi.swift
//  SenseBLETester
//
//  Created by Jimmy Lu on 11/17/14.
//  Copyright (c) 2014 Hello, Inc. All rights reserved.
//

import Foundation

class STSenseSetWiFi : STSenseTestOperation {
    
    override func execute() {
        super.execute()
        
        let ssid:String! = "Hello"
        let pass:String! = "godsavethequeen"
        let type:SENWifiEndpointSecurityType = SENWifiEndpointSecurityTypeWpa2
        self.senseManager.setWiFi(
            ssid,
            password : pass,
            securityType : type,
            success: { (response : AnyObject?) -> Void in
                self.done(nil)
            }, failure : { (error : NSError?) -> Void in
                self.done(error)
            })
    }
    
}
