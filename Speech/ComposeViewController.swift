//
// Copyright 2016 Google Inc. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
import UIKit
import AVFoundation
import googleapis
import FirebaseAuth
import FirebaseDatabase

//let SAMPLE_RATE = 16000
let SAMPLE_RATE = 44100.0

class ComposeViewController : UIViewController, AudioControllerDelegate, CanSpeakDelegate {
    @IBOutlet weak var textView: UITextView!
    @IBOutlet weak var startButton: UIButton!
    @IBOutlet weak var pauseButton: UIButton!
    
    var userId: String?
    var ref: FIRDatabaseReference?
    
    var audioData: NSMutableData!
    var textToSpeechTimerBackground = Timer()
    var backgroundTask = BackgroundTask()
    var audioEngine = AVAudioEngine()
    var userInput = String()
    var sessionStarted = false
    var clockTimer = 0
    
    let synth = AVSpeechSynthesizer()
    let canSpeak = CanSpeak()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.canSpeak.delegate = self
        AudioController.sharedInstance.delegate = self
        ref = FIRDatabase.database().reference()
        userId = FIRAuth.auth()?.currentUser?.uid
        textView.isEditable = false
        setupSessionForRecording()
    }
    
    @IBAction func recordAudio(_ sender: NSObject) {
        print("button pressed")
        startButton.alpha = 0.5
        startButton.isUserInteractionEnabled = false
        pauseButton.alpha = 1
        pauseButton.isUserInteractionEnabled = true
        
        backgroundTask.startBackgroundTask()
        askUser()
        textToSpeechTimerBackground = Timer.scheduledTimer(timeInterval: 1800, target: self, selector: #selector(self.askUser), userInfo: nil, repeats: true)
        _ = Timer.scheduledTimer(timeInterval: 30, target: self, selector: #selector(self.clockTick), userInfo: nil, repeats: true)
        self.sessionStarted = true
    }
    
    func clockTick() {
        clockTimer = clockTimer + 30
        print (String(clockTimer / 60) + " minutes and " +  String(clockTimer % 60) + " seconds have passed")
    }
    
    func setupSessionForRecording() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(AVAudioSessionCategoryPlayAndRecord, with: [.allowBluetooth])
        } catch {
            fatalError("Error Setting Up Audio Session")
        }
        var inputsPriority: [(type: String, input: AVAudioSessionPortDescription?)] = [
            (AVAudioSessionPortLineIn, nil),
            (AVAudioSessionPortHeadsetMic, nil),
            (AVAudioSessionPortBluetoothHFP, nil),
            (AVAudioSessionPortUSBAudio, nil),
            (AVAudioSessionPortCarAudio, nil),
            (AVAudioSessionPortBuiltInMic, nil),
            ]
        for availableInput in audioSession.availableInputs! {
            guard let index = inputsPriority.index(where: { $0.type == availableInput.portType }) else { continue }
            inputsPriority[index].input = availableInput
        }
        guard let input = inputsPriority.filter({ $0.input != nil }).first?.input else {
            fatalError("No Available Ports For Recording")
        }
        do {
            try audioSession.setPreferredInput(input)
            try audioSession.setActive(true)
        }
        catch {
            fatalError("Error Setting Up Audio Session")
        }
    }
    
    func askUser() {
        backgroundTask.pauseBackgroundTask()
        self.canSpeak.sayThis("Hello, What are you doing right now?")
    }
    
    @IBAction func cancelPost(_ sender: Any) {
        startButton.alpha = 1
        startButton.isUserInteractionEnabled = true
        pauseButton.alpha = 0.5
        pauseButton.isUserInteractionEnabled = false
        
        if self.sessionStarted {
            audioEngine.stop()
            self.stopAudioTemp()
            backgroundTask.stopBackgroundTask()
            textToSpeechTimerBackground.invalidate()
        }
        
        self.sessionStarted = false
        presentingViewController?.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func stopAudio(_ sender: NSObject) {
        print("stopping the audio")
        startButton.alpha = 1
        startButton.isUserInteractionEnabled = true
        pauseButton.alpha = 0.5
        pauseButton.isUserInteractionEnabled = false
        
        _ = AudioController.sharedInstance.stop()
        SpeechRecognitionService.sharedInstance.stopStreaming()
        backgroundTask.stopBackgroundTask()
        textToSpeechTimerBackground.invalidate()
        self.sessionStarted = false
    }
    
    func recordUser() {
        if !self.synth.isSpeaking {

//            setupSessionForRecordingp()
            let audioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setCategory(AVAudioSessionCategoryPlayAndRecord, with: [.allowBluetooth])
            } catch {
                fatalError("Error Setting Up Audio Session")
            }
            
            print ("You can say something now!")
            
            self.textView.text = "You can say something now"
            audioData = NSMutableData()
            _ = AudioController.sharedInstance.prepare(specifiedSampleRate: Int(SAMPLE_RATE))
            SpeechRecognitionService.sharedInstance.sampleRate = Int(SAMPLE_RATE)
            _ = AudioController.sharedInstance.start()
            
            if #available(iOS 10.0, *) {
                _ = Timer.scheduledTimer(withTimeInterval: 20, repeats: false, block: { (timer) in
                    self.stopAudioTemp()
                    print("in timer")
                    do {
                        if self.userInput == "" {
                            print("no response from the user")
                            self.userInput = "No Response From User"
                            self.textView.text = self.userInput
                            let audioSession = AVAudioSession.sharedInstance()
                            try audioSession.setCategory(AVAudioSessionCategoryPlayback)
//                            try audioSession.setActive(false, with: .notifyOthersOnDeactivation)
                            self.backgroundTask.startBackgroundTask()
                            self.addPostFunc()
                            print("after 20 seconds")
                        }
                        self.userInput = ""
                    } catch {
                        // handle errors
                    }
                    print("timer has ended")
                })
            } else {
                // Fallback on earlier versions
            }
        }
    }
    
    func convertToDictionary(text: String) -> [String: Any]? {
        if let data = text.data(using: .utf8) {
            do {
                return try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            } catch {
                print(error.localizedDescription)
            }
        }
        return nil
    }
    
    func stopAudioTemp() {
        _ = AudioController.sharedInstance.stop()
        SpeechRecognitionService.sharedInstance.stopStreaming()
    }
    
    func processSampleData(_ data: Data) -> Void {
        audioData.append(data)
        
        // We recommend sending samples in 100ms chunks
        let chunkSize : Int /* bytes/chunk */ = Int(0.1 /* seconds/chunk */
            * Double(SAMPLE_RATE) /* samples/second */
            * 2 /* bytes/sample */);
        
        if (audioData.length > chunkSize) {
            SpeechRecognitionService.sharedInstance.streamAudioData(audioData,
                                                                    completion:
                { [weak self] (response, error) in
                    guard let strongSelf = self else {
                        return
                    }
                    
                    if let error = error {
                        strongSelf.textView.text = error.localizedDescription
                        self?.userInput = error.localizedDescription
                        self?.doneWithRecording()
                        
                    } else if let response = response {
                        var finished = false
                        //                        print(response)
                        for result in response.resultsArray! {
                            if let result = result as? StreamingRecognitionResult {
                                if result.isFinal {
                                    finished = true
                                    let test = result.alternativesArray[0] as! SpeechRecognitionAlternative
                                    print ("data: " + String(describing: test.transcript!))
                                    strongSelf.userInput = String(describing: test.transcript!)
                                }
                            }
                        }
//                        strongSelf.textView.text = response.description
                        
                        if finished {
                            strongSelf.textView.text = self?.userInput
                            strongSelf.doneWithRecording()
//                            strongSelf.textView.text = self?.userInput
//                            strongSelf.stopAudioTemp()
//                            do {
//                                print ("finished recording")
//                                let audioSession = AVAudioSession.sharedInstance()
//                                try audioSession.setCategory(AVAudioSessionCategoryPlayback)
//                                self?.backgroundTask.startBackgroundTask()
//                                self?.addPostFunc()
//                            } catch {
//                                // handle errors
//                            }
                        }
                    }
            })
            self.audioData = NSMutableData()
        }
    }
    
    func speechDidFinish() {
        self.recordUser()
    }
    
    func doneWithRecording() {
        self.stopAudioTemp()
        do {
            print ("finished recording")
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(AVAudioSessionCategoryPlayback)
            self.backgroundTask.startBackgroundTask()
            self.addPostFunc()
        } catch {
            // handle errors
        }
    }
    
    func addPostFunc () {
        let todaysDate:NSDate = NSDate()
        let dateFormatter:DateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM-dd-yyyy"
        let todayString:String = dateFormatter.string(from: todaysDate as Date)
        let date = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minutes = calendar.component(.minute, from: date)
        let idReference = self.ref?.child("users").child(userId!).child("Posts").childByAutoId()
        let stringReferenceArr = String(describing: idReference!).components(separatedBy: "/")
        let stringReference = stringReferenceArr[stringReferenceArr.count - 1]
        idReference!.setValue(["message": self.userInput, "date": todayString, "hour": hour, "minutes": minutes, "reference" : stringReference])
    }
}
