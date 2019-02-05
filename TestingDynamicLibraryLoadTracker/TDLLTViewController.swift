//
//  TDLLTViewController.swift
//  TestingDynamicLibraryLoadTracker
//
//  Created by Ignat Remizov on 11/10/15.
//  Copyright © 2019 Ignat Remizov. All rights reserved.
//

import UIKit
import DynamicLibraryLoadTracker

class TDLLTViewController: UIViewController {
    
    private lazy var __once: () = {[unowned self] in
            self.tracker.printLastLog()
        }()
    
    @IBOutlet var tableView: UITableView!
    var tracker: DynamicLibraryLoadTracker!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //This is used to reload the table view when the app is opened from background, usually more libraries are loaded
        NotificationCenter.default.addObserver(self, selector: #selector(TDLLTViewController.updateTableView), name: NSNotification.Name.UIApplicationDidBecomeActive , object: nil)
    }
    
    ///Print after UI is loaded
    var predicate = Int()
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        _ = self.__once
    }
    
    func updateTableView() {
        tableView.reloadData()
    }
    
}

extension TDLLTViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return 1
        } else {
            return tracker.log.count
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell:UITableViewCell
        if let dequedCell = tableView.dequeueReusableCell(withIdentifier: "libCell") {
            cell = dequedCell
        } else {
            cell = UITableViewCell(style: .default, reuseIdentifier: "libCell")
        }
        if (indexPath as NSIndexPath).section == 1 {
            cell.textLabel?.text = tracker.log.object(at: (indexPath as NSIndexPath).row) as? String
        } else {
            cell.textLabel?.text = "Total log entries: \(tracker.log.count)"
        }
        return cell
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
}
