//
//  SettingsViewController.swift
//  Speech
//
//  Created by Ka Tai Ho on 3/8/18.
//  Copyright © 2018 Google. All rights reserved.
//

import UIKit
import AVFoundation

class SettingsViewController: UIViewController, UIPickerViewDataSource, UIPickerViewDelegate, CanSpeakDelegate {

    @IBOutlet weak var textBox: UITextField!
    @IBOutlet weak var userTimeInterval: UITextField!
    
    @IBAction func goBack(_ sender: Any) {
        presentingViewController?.dismiss(animated: true, completion: nil)
    }
    
    let canSpeak = CanSpeak()
    var pickerView = UIPickerView()
    var userPickedVoice = String("")
    
    var voices = ["Karen", "Daniel", "Moira", "Samantha", "Tessa", "Monica"]
    
    @IBAction func saveButton(_ sender: Any) {
        if userPickedVoice != "" && userTimeInterval.text != "" {
            UserDefaults.standard.set(userPickedVoice, forKey: "voice")
            UserDefaults.standard.set(Int(userTimeInterval.text!)! * 60, forKey: "userTimeInterval")
            print("saved the users selected voice")
            print("The user selected " + String(Int(userTimeInterval.text!)! * 60))
            
            textBox.text = ""
            userTimeInterval.text = ""
            presentingViewController?.dismiss(animated: true, completion: nil)
        }
        
    }
    
    func testVoice (v: String) {

        
        let audioSession = AVAudioSession.sharedInstance()  //2
        do
        {
            try audioSession.setCategory(AVAudioSessionCategoryPlayAndRecord)
            try audioSession.setMode(AVAudioSessionModeDefault)
            //try audioSession.setMode(AVAudioSessionModeMeasurement)
            try audioSession.setActive(true, with: .notifyOthersOnDeactivation)
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(AVAudioSessionPortOverride.speaker)
        }
        catch
        {
            print("audioSession properties weren't set because of an error.")
        }
        canSpeak.testVoice(voice: v, phrase: "Hello, my name is " + v, speed: 0.5)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.canSpeak.delegate = self
        pickerView.delegate = self
        pickerView.dataSource = self
        
        textBox.inputView = pickerView
        textBox.textAlignment = .center
        textBox.placeholder = "Select Voice"
        // Do any additional setup after loading the view.
    }

    public func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    public func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return voices.count
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return voices[row]
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        userPickedVoice = voices[row]
        textBox.text = userPickedVoice
        textBox.resignFirstResponder()
        testVoice(v: userPickedVoice!)
    }
    
    func speechDidFinish() {

    }
}