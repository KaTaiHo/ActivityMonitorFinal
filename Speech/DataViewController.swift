//
//  DataViewController.swift
//  ActivityMonitor
//
//  Created by Ka Tai Ho on 8/29/17.
//  Copyright © 2017 SDLtest. All rights reserved.
//

import UIKit
import FirebaseAuth
import FirebaseDatabase

class DataViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    @IBOutlet weak var tableView: UITableView!
    var postData = [String]()
    var referenceArr = [String]()
    var ref:DatabaseReference?
    var databaseHandle:DatabaseHandle?
    
    struct activityData {
        var activity:String
        var datetime:String
    }
    
    var postDataWrapper = [activityData]()
    
    override func loadView() {
        super.loadView()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.delegate = self;
        tableView.dataSource = self;
        ref = Database.database().reference()
        let userId = Auth.auth().currentUser?.uid
        
        ref?.child("users").child(userId!).child("Posts").observeSingleEvent(of: .value, with: { snapshot in
            print(snapshot.childrenCount) // I got the expected number of items
            for rest in snapshot.children.allObjects as! [DataSnapshot] {
                guard let restDict = rest.value as? [String: Any] else { continue }
                print(restDict)
                let message = restDict["message"] as? String
                let referenceStr = restDict["reference"] as? String
                
                self.postData.insert(message!, at: 0)
                self.referenceArr.insert(referenceStr!, at: 0)
            }
            if self.postData.count > 0 {
                self.postData.remove(at: 0)
                self.referenceArr.remove(at: 0)
            }
            
            self.tableView.reloadData()
        })
        
        ref?.child("users").child(userId!).child("Posts").queryLimited(toLast: 1).observe(.childAdded, with: { snapshot in
                guard let temp = snapshot.value as? [String: Any] else { return }
                
                let message = temp["message"] as? String
                let referenceStr = temp["reference"] as? String
                
                self.postData.insert(message!, at: 0)
                self.referenceArr.insert(referenceStr!, at: 0)
                
                print(snapshot.value!)
                self.tableView.reloadData()
        })
    }
    
    @IBAction func logout(_ sender: UIBarButtonItem) {
        try! Auth.auth().signOut()
        presentingViewController?.dismiss(animated: true, completion: nil)
    }
    
// allow user to delete entry
//    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
//        if editingStyle == UITableViewCellEditingStyle.delete {
//            guard let uid = Auth.auth().currentUser?.uid else {
//                return
//            }
//
//            let post = self.referenceArr[indexPath.row]
//            print(post)
//
//            Database.database().reference().child("users").child(uid).child("Posts").child(post).removeValue(completionBlock: { (error, ref) in
//                if error != nil {
//                    print("Failed to Delete Message", error!)
//                    return
//                }
//            })
//
//            self.postData.remove(at: indexPath.row)
//            self.referenceArr.remove(at: indexPath.row)
//
//            tableView.reloadData()
//        }
//    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PostCell")
        cell?.textLabel?.text = postData[indexPath.row]
        return cell!
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return postData.count
    }
}
