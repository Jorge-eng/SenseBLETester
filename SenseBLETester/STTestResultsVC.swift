//
//  STTestResultsVC.swift
//  SenseBLETester
//
//  Created by Jimmy Lu on 11/20/14.
//  Copyright (c) 2014 Hello, Inc. All rights reserved.
//

import UIKit

class STTestResultsVC: UIViewController, UITableViewDelegate {
    
    @IBOutlet weak var resultsTableView: UITableView!
    
    var testSuite : STSenseTestSuite?
    var dataSource : STTestResultDataSource?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = self.testSuite?.senseManager.sense.name
        self.dataSource = STTestResultDataSource(testSuite: self.testSuite!)
        self.resultsTableView.dataSource = self.dataSource
        self.resultsTableView.tableFooterView = UIView()
    }
    
    // MARK: Table View Delegate
    func tableView(tableView: UITableView, willDisplayCell cell: UITableViewCell, forRowAtIndexPath indexPath: NSIndexPath) {
        let name = self.dataSource!.testNameAtIndexPath(indexPath)
        let code = self.dataSource!.testResultCodeAtIndexPath(indexPath)
        
        cell.textLabel.text = name
        cell.detailTextLabel?.text = String(code)
    }
    
}


