//
//  MainViewController.swift
//  Speech
//
//  Created by Ka Tai Ho on 12/17/17.
//  Copyright © 2017 Google. All rights reserved.
//

import UIKit
import FirebaseAuth
import FirebaseDatabase

class MainViewController: UIViewController {

    @IBOutlet weak var _prefname: UITextField!
    @IBOutlet weak var signInSelector: UISegmentedControl!
    @IBOutlet weak var _username: UITextField!
    @IBOutlet weak var _password: UITextField!
    @IBOutlet weak var _login_button: UIButton!
    var ref: FIRDatabaseReference?
    
    var isSignIn:Bool = true
    
    override func loadView() {
        super.loadView()
        _login_button.backgroundColor = UIColor(hex: "27B4FF")
        _login_button.layer.cornerRadius = 10;
        _login_button.clipsToBounds = true;
        _prefname.isHidden = true
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        ref = FIRDatabase.database().reference()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    

    @IBAction func signInSelectorChanged(_ sender: UISegmentedControl) {
        isSignIn = !isSignIn
        
        if isSignIn {
            _prefname.isHidden = true
            _login_button.setTitle("Sign In", for: .normal)
        }
        else {
            _prefname.isHidden = false
            _login_button.setTitle("Register", for: .normal)
        }
    }
    
    @IBAction func signInButtonTapped(_ sender: UIButton) {
        // TODO: form validation
        if let email = _username.text, let pass = _password.text {
            if isSignIn {
                FIRAuth.auth()?.signIn(withEmail: email, password: pass, completion: {(user, error) in
                    if user != nil {
                        self.performSegue(withIdentifier: "goToData", sender: self)
                    }
                    else {
                        print("error trying to login")
                    }
                })
            }
            else {
                if let prefnameText = _prefname.text?.trimmingCharacters(in: .whitespacesAndNewlines), _prefname.hasText {
                    FIRAuth.auth()?.createUser(withEmail: email, password: pass, completion: {
                        (user, error) in
                        if user != nil {
                            if error != nil {
                                print(error!.localizedDescription)
                                return
                            }
                            let userReference = self.ref?.child("users")
                            let uid = user?.uid
                            let newUserReference = userReference?.child(uid!)
                            let emptyString: [String] = []
                            newUserReference?.setValue(["email": self._username.text!, "Posts": emptyString, "prefname": prefnameText])
                            
                            //go to home screen
                            self.performSegue(withIdentifier: "goToData", sender: self)
                        }
                        else {
                            //error
                            print("error trying to register")
                        }
                    })
                }
            }
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        _username.resignFirstResponder()
        _password.resignFirstResponder()
    }
}
