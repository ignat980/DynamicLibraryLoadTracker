//
//  TDLLTViewController.swift
//  TestingDynamicLibraryLoadTracker
//
//  Created by IR on 11/10/15.
//  Copyright © 2015 IR. All rights reserved.
//

import UIKit
import DynamicLibraryLoadTracker

class TDLLTViewController: UIViewController {
    
    @IBOutlet var tableView: UITableView!
    var tracker: DynamicLibraryLoadTracker!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //This is used to reload the table view when the app is opened from background, usually more libraries are loaded
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "updateTableView", name: UIApplicationDidBecomeActiveNotification , object: nil)
    }
    
    ///Print after UI is loaded
    var predicate = dispatch_once_t()
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        dispatch_once(&predicate) {[unowned self] in
            self.tracker.printLastLog()
        }
    }
    
    func updateTableView() {
        tableView.reloadData()
    }
    
}

extension TDLLTViewController: UITableViewDataSource {
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return 1
        } else {
            return tracker.log.count
        }
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell:UITableViewCell
        if let dequedCell = tableView.dequeueReusableCellWithIdentifier("libCell") {
            cell = dequedCell
        } else {
            cell = UITableViewCell(style: .Default, reuseIdentifier: "libCell")
        }
        if indexPath.section == 1 {
            cell.textLabel?.text = tracker.log.objectAtIndex(indexPath.row) as? String
        } else {
            cell.textLabel?.text = "Total log entries: \(tracker.log.count)"
        }
        return cell
    }
    
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 2
    }
}
