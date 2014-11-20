//
//  STTestResultDataSource.swift
//  SenseBLETester
//
//  Created by Jimmy Lu on 11/20/14.
//  Copyright (c) 2014 Hello, Inc. All rights reserved.
//

import Foundation
import UIKit

class STTestResultDataSource : NSObject, UITableViewDataSource {
    
    private var tests : [SenseTestType]
    
    var testSuite : STSenseTestSuite
    
    init(testSuite : STSenseTestSuite) {
        self.testSuite = testSuite
        self.tests = testSuite.testsInSuite()
    }
    
    func testNameAtIndexPath(indexPath: NSIndexPath) -> String {
        return self.tests[indexPath.row].rawValue
    }
    
    func testResultCodeAtIndexPath(indexPath : NSIndexPath) -> Int {
        let type = self.tests[indexPath.row]
        return self.testSuite.testResultCodeFor(type)
    }
    
    // MARK: TableView Data Source
    
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.tests.count
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        return tableView.dequeueReusableCellWithIdentifier("test", forIndexPath: indexPath) as UITableViewCell
    }
    
}