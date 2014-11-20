//
//  ViewController.swift
//  SenseBLETester
//
//  Created by Jimmy Lu on 11/17/14.
//  Copyright (c) 2014 Hello, Inc. All rights reserved.
//

import UIKit

class STRootVC: UIViewController, UITableViewDelegate {
    
    @IBOutlet weak var senseTableView:UITableView!
    @IBOutlet weak var scanButton:UIButton!
    @IBOutlet weak var clearButton: UIBarButtonItem!
    @IBOutlet weak var testButton: UIButton!
    @IBOutlet weak var activityView: UIView!
    
    private var dataSource : STSenseDataSource?
    private var selectedTestSuite : STSenseTestSuite?
    private var loaded = false

    override func viewDidLoad() {
        super.viewDidLoad()
        self.dataSource = STSenseDataSource(tableView: self.senseTableView);
        self.senseTableView.dataSource = self.dataSource;
        self.senseTableView.delegate = self;
        self.senseTableView.tableFooterView = UIView()
        self.scanButton.layer.borderWidth = 0.5
        self.scanButton.layer.borderColor = UIColor.blackColor().colorWithAlphaComponent(0.1).CGColor
        self.testButton.layer.borderColor = UIColor.blackColor().colorWithAlphaComponent(0.1).CGColor
        self.testButton.layer.borderWidth = 0.5
        self.testButton.enabled = self.dataSource!.haveSensesToTest()
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        if !self.loaded {
            self.scan(self.scanButton)
            self.loaded = true
        }
        
    }
    
    // MARK: - Table View -
    
    func tableView(tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 30
    }
    
    func tableView(tableView: UITableView, willDisplayCell cell: UITableViewCell, forRowAtIndexPath indexPath: NSIndexPath) {
        let sense:SENSense! = self.dataSource!.senseAtIndexPath(indexPath)
        var name = sense.name
        var status : String
        
        switch self.dataSource!.statusForSenseAtIndexPath(indexPath) {
        case STSenseTestStatus.InProgress:
            status = "in progress"
            break
        case STSenseTestStatus.Failed:
            status = "failed"
            break
        case STSenseTestStatus.Passed:
            status = "passed"
            break
        default:
            if indexPath.section == STSenseSection.Found.rawValue {
                status = "Add For Testing"
            } else if indexPath.section == STSenseSection.Ready.rawValue {
                status = "Waiting"
            } else {
                status = ""
            }
            break
        }
        
        cell.detailTextLabel?.text = status
        cell.textLabel.text = name
    }
    
    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        tableView.deselectRowAtIndexPath(indexPath, animated: true)
        
        if indexPath.section == STSenseSection.Found.rawValue {
            let sense = self.dataSource!.senseAtIndexPath(indexPath)
            self.showActivity(true)
            self.dataSource!.addSenseToTest(sense!, completion: { [weak self] (Void) -> Void in
                if (self? != nil) {
                    self!.senseTableView.reloadData()
                    self!.showActivity(false)
                    self!.testButton.enabled = self!.dataSource!.haveSensesToTest()
                }
            })
        } else if indexPath.section == STSenseSection.Tested.rawValue {
            self.selectedTestSuite = self.dataSource!.testSuiteAtIndexPath(indexPath)
            self.performSegueWithIdentifier("detail", sender: self)
        }

    }
    
    private func showActivity(show: Bool) {
        self.enableButtons(!show)
        
        if (show) {
            self.activityView.alpha = 0
            self.activityView.hidden = false
            UIView.animateWithDuration(0.35, animations: { () -> Void in
                self.activityView.alpha = 1
            })
        } else {
            UIView.animateWithDuration(0.35, animations: { () -> Void in
                self.activityView.alpha = 0
            }, completion: { (finished: Bool) -> Void in
                self.activityView.hidden = true
            })
        }
    }
    
    private func enableButtons(enable : Bool) {
        self.scanButton.enabled = enable
        self.clearButton.enabled = enable
        self.testButton.enabled = enable && self.dataSource!.haveSensesToTest()
    }
    
    // MARK: - Actions -
    
    @IBAction func clear(sender: AnyObject) {
        self.dataSource!.clear()
        self.testButton.enabled = false
    }
    
    @IBAction func scan(sender: AnyObject) {
        self.enableButtons(false)
        self.dataSource!.rescan { [weak self] (Void) -> Void in
            if (self? == nil) {
                return;
            }
            self!.senseTableView.reloadData();
            self!.enableButtons(true)
        }
    }
    
    @IBAction func test(sender: AnyObject) {
        self.enableButtons(false)
        self.dataSource!.startTesting { [weak self](Void) -> Void in
            if (self? != nil) {
                self!.senseTableView.reloadData()
                self!.enableButtons(true)
            }
        }
    }
    
    // MARK: DETAIL
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        let dest = segue.destinationViewController as UIViewController
        if let detailVC = dest as? STTestResultsVC {
            detailVC.testSuite = self.selectedTestSuite
        }
    }
}

