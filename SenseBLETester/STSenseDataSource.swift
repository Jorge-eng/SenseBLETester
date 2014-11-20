//
//  STSenseDataSource.swift
//  SenseBLETester
//
//  Created by Jimmy Lu on 11/17/14.
//  Copyright (c) 2014 Hello, Inc. All rights reserved.
//

import Foundation
import UIKit

enum STSenseTestStatus {
    case NotReady, InProgress, Failed, Passed
}

enum STSenseSection : Int {
    case Found = 0, Ready = 1, Tested = 2
}

class STSenseDataSource : NSObject, UITableViewDataSource {
    
    private var discoveredSenses = [SENSense]()
    private var senseReadyForTest = [SENSense]()
    private var senseTested = [SENSense]()
    private var testSuites = NSMutableDictionary()
    private var tempManager : SENSenseManager?
    
    let tableView : UITableView
    
    init(tableView : UITableView) {
        self.tableView = tableView
    }
    
    func senseAtIndexPath(indexPath:NSIndexPath) -> SENSense? {
        var sense:SENSense?;
        if indexPath.section == STSenseSection.Found.rawValue && indexPath.row < self.discoveredSenses.count {
            sense = self.discoveredSenses[indexPath.row]
        } else if indexPath.section == STSenseSection.Ready.rawValue && indexPath.row < self.senseReadyForTest.count {
            sense = self.senseReadyForTest[indexPath.row]
        } else if indexPath.section == STSenseSection.Tested.rawValue && indexPath.row < self.senseTested.count {
            sense = self.senseTested[indexPath.row]
        }
        return sense;
    }
    
    func testSuiteAtIndexPath(indexPath:NSIndexPath) -> STSenseTestSuite? {
        if indexPath.section == 0 {
            return nil
        }
        var suite:STSenseTestSuite?
        let sense = self.senseAtIndexPath(indexPath)
        if sense != nil {
            suite = self.testSuites[sense!.deviceId] as? STSenseTestSuite
        }
        return suite
    }
    
    func haveSensesToTest() -> Bool {
        return self.senseReadyForTest.count > 0
    }
    
    func isTesting(indexPath:NSIndexPath) -> Bool {
        let suite = self.testSuiteAtIndexPath(indexPath)
        var testing = false
        if (suite? != nil) {
            testing = suite!.done
        }
        return testing
    }
    
    func statusForSenseAtIndexPath(indexPath:NSIndexPath) -> STSenseTestStatus {
        var status : STSenseTestStatus
        let testSuite = self.testSuiteAtIndexPath(indexPath)
        
        if testSuite? == nil {
            status = STSenseTestStatus.NotReady
        } else if !testSuite!.done {
            status = STSenseTestStatus.InProgress
        } else if testSuite!.success {
            status = STSenseTestStatus.Passed
        } else {
            status = STSenseTestStatus.Failed
        }
        
        return status
    }
    
    func clear() {
        self.discoveredSenses.removeAll(keepCapacity: true)
        self.senseReadyForTest.removeAll(keepCapacity: true)
        self.senseTested.removeAll(keepCapacity: true)
        self.testSuites.removeAllObjects()
        self.tableView.reloadData()
    }
    
    func rescan(completion: (Void) -> Void) -> Void {
        
        self.discoveredSenses.removeAll(keepCapacity: true)
        self.tableView.reloadData()
        
        let ready = SENSenseManager.scanForSense { [weak self] (senses : [AnyObject]?) -> Void in
            if self? == nil {
                return;
            }
            if senses?.count > 0 {
                // FIXME: write some Swift algorithms!
                for sense in senses as [SENSense] {
                    var found = false
                    
                    for senseForTest in self!.senseReadyForTest {
                        if (senseForTest == sense) {
                            found = true
                            break
                        }
                    }
                    
                    if (!found) {
                        for testedSense  in self!.senseTested {
                            if (testedSense == sense) {
                                found = true
                                break
                            }
                        }
                    }
                    
                    if (!found) {
                        self!.discoveredSenses.append(sense)
                    }
                }
            }
            completion()
        }
        
        if (!ready) {
            dispatch_after(1, dispatch_get_main_queue(), {
                self.rescan(completion);
            })
        }
    }
    
    func addSenseToTest(sense: SENSense, completion: (Void) -> Void) -> Void {
        self.tempManager = SENSenseManager(sense: sense);
        self.tempManager!.pair({[weak self] (response: AnyObject?) -> Void in
            if (self? == nil) {
                return;
            }
            self!.senseReadyForTest.append(sense);
            self!.tempManager?.disconnectFromSense()
            self!.tempManager = SENSenseManager() // clear it out
            
            let index = find(self!.discoveredSenses, sense)
            if (index >= 0 && index < self!.discoveredSenses.count) {
                self!.discoveredSenses.removeAtIndex(index!)
            }
            
            completion()
        }, failure: { (error: NSError!) -> Void in
            // TODO: implement failures
            completion()
        })
    }
    
    private func rescanFor(sense: SENSense, completion : (sense: SENSense?) -> Void) {
        println("rescanning for sense ", sense.name)
        let ready = SENSenseManager.scanForSense { [weak self] (senses : [AnyObject]?) -> Void in
            var foundSense : SENSense?
            for scannedSense in senses as [SENSense] {
                if (scannedSense == sense) {
                    foundSense = scannedSense
                    break
                }
            }
            completion (sense: foundSense)
        }
        if (!ready) {
            self.rescanFor(sense, completion: completion)
        }
    }
    
    func startTesting(completion : (Void) -> Void) {
        // TODO: move this in to a testQueue
        if (self.senseReadyForTest.count > 0) {
            let sense = self.senseReadyForTest.last
            
            self.rescanFor(sense!, completion: { [weak self] (sense: SENSense?) -> Void in
                if (self? == nil) { return }
                let manager = SENSenseManager(sense: sense);
                let testSuite = STSenseTestSuite(senseManager: manager)
                println("sense device id ", sense!.deviceId)
                self!.testSuites[sense!.deviceId] = testSuite
                println("sense test suite count ", self!.testSuites.count)
                
                testSuite.onDone = {[weak self] (Void) -> Void in
                    if (self? != nil) {
                        println("sense ", sense!.name, "is done testing")
                        self!.senseReadyForTest.removeLast()
                        self!.senseTested.append(sense!)
                        self!.tableView.reloadData()
                        self!.startTesting(completion)
                    }
                }
                testSuite.onUpdate = {[weak self] (Void) -> Void in
                    if (self? != nil) {
                        self!.tableView.reloadData()
                    }
                }
                
                println("testing sense ", sense!.name)
                self!.tableView.reloadData()
                testSuite.start()
            })

        } else {
            println("no more sense to test")
            completion()
        }
    }
    
    // MARK: - UITableView Methods
    
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 3;
    }
    
    func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        var tableTitle : String
        switch section {
        case STSenseSection.Ready.rawValue:
            tableTitle = "Ready for testing"
            break;
        case STSenseSection.Tested.rawValue:
            tableTitle = "Tested"
            break;
        default:
            tableTitle = "Found"
            break;
        }
        return tableTitle
    }

    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        var count : Int
        switch section {
        case STSenseSection.Found.rawValue:
            count = self.discoveredSenses.count
            break;
        case STSenseSection.Ready.rawValue:
            count = self.senseReadyForTest.count
            break;
        case STSenseSection.Tested.rawValue:
            count = self.senseTested.count
            break;
        default:
            count = 0
            break;
        }
        return count
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let senseReuseCellId:NSString = "sense"
        return tableView.dequeueReusableCellWithIdentifier(senseReuseCellId, forIndexPath: indexPath) as UITableViewCell
    }
    
}
