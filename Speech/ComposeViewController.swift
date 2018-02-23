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
import MicrosoftBand
import SystemConfiguration


//let SAMPLE_RATE = 16000
let SAMPLE_RATE = 44100.0

class ComposeViewController : UIViewController, AudioControllerDelegate, CanSpeakDelegate, ConnectionDelegate, MSBClientManagerDelegate, MSBClientTileDelegate {
    
    
    @IBOutlet weak var textView: UITextView!
    @IBOutlet weak var startButton: UIButton!
    @IBOutlet weak var pauseButton: UIButton!
    
    var userId: String?
    var ref: DatabaseReference?
    
    weak var client: MSBClient?
    
    let tileID = NSUUID(uuidString: "CDBDBA9F-12FD-47A5-8453-E7270A43BB99")
    
    var audioData: NSMutableData!
    var textToSpeechTimerBackground = Timer()
    var backgroundTask = BackgroundTask()
    var audioEngine = AVAudioEngine()
    var userInput = String()
    var sessionStarted = false
    var clockTimer = 0
    
    let synth = AVSpeechSynthesizer()
    let canSpeak = CanSpeak()
    let audioSession = AVAudioSession.sharedInstance()
    var firstResponse = ""
    
    var needToCheckInput = true
    
    var timerForRecording = Timer()
    
    let semaphore = DispatchSemaphore(value: 1)
    
    var askUserFlag = true
    
    var globalTile = MSBTile()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.canSpeak.delegate = self
        AudioController.sharedInstance.delegate = self
        ref = Database.database().reference()
        userId = Auth.auth().currentUser?.uid
        textView.isEditable = false
        setupSessionForRecording()
        
        MSBClientManager.shared().delegate = self
        if let client = MSBClientManager.shared().attachedClients().first as? MSBClient {
            self.client = client
            // 2. Set Tile Event Delegate
            client.tileDelegate = self;
            
            MSBClientManager.shared().connect(self.client)
            print("Please wait. Connecting to Band...")
        } else {
            print("Failed! No Bands attached.")
        }
    }
    
    
    @IBAction func recordAudio(_ sender: NSObject) {
        if client?.isDeviceConnected == true {
            print("button pressed")
            SpeechRecognitionService.sharedInstance.sampleRate = Int(SAMPLE_RATE)
            startButton.alpha = 0.5
            startButton.isUserInteractionEnabled = false
            pauseButton.alpha = 1
            pauseButton.isUserInteractionEnabled = true
            
            backgroundTask.startBackgroundTask()
            //        checkUserInput()
            MBandSetUp()
            textToSpeechTimerBackground = Timer.scheduledTimer(timeInterval: 300, target: self, selector: #selector(self.MBandSetUp), userInfo: nil, repeats: true)
            
            _ = Timer.scheduledTimer(timeInterval: 30, target: self, selector: #selector(self.clockTick), userInfo: nil, repeats: true)
            self.sessionStarted = true
        }
        // tell the user to wait for the band to connect TODO
    }
    
    func clockTick() {
        clockTimer = clockTimer + 30
        print (String(clockTimer / 60) + " minutes and " +  String(clockTimer % 60) + " seconds have passed")
    }
    
    func MBSBaskUser() {
        if self.isConnectedToNetwork() {
            MBandSetUp()
        }
        else {
            print("The user is not connected to the internet")
        }
    }
    
    func setupSessionForRecording() {
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
        
        needToCheckInput = true
        self.canSpeak.sayThis("Hello, What are you doing right now?", speed: 0.5)
    }
    
    func askUserAgain() {
        backgroundTask.pauseBackgroundTask()
        needToCheckInput = true
        self.canSpeak.sayThis("Could you please repeat what you said?", speed: 0.5)
    }
    
    func checkUserInput(){
        
        backgroundTask.pauseBackgroundTask()
        firstResponse = self.userInput
        semaphore.wait()
//        needToCheckInput = false
        semaphore.signal()
        self.canSpeak.sayThis("Did you say" + self.userInput, speed: 0.5)
        
        print("user said " + self.userInput)
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
    
    func MSBSendMessage() {
        
    }
    
    func MBandSetUp() {
        print ("button pressed")
        if let client = self.client {
            print("inside client")
            if client.isDeviceConnected == false {
                print("Band is not connected. Please wait....")
                return
            }
            print("Button tile...")
            let tileName = "D tile"
            let titleIcon = try? MSBIcon(uiImage: UIImage(named:"D.png")) 
            let smallIcon = try? MSBIcon(uiImage: UIImage(named:"Dd.png"))
            
            let tile = try? MSBTile(id: tileID! as UUID, name: tileName, tileIcon: titleIcon, smallIcon: smallIcon)
            tile?.isBadgingEnabled
            
            globalTile = tile!
            
            let textBlock = MSBPageTextBlock(rect: MSBPageRect(x: 0, y: 0, width: 200, height: 40), font: MSBPageTextBlockFont.small)
            textBlock?.elementId = 10
            //            textBlock?.color = MSBColor.colorWithUIColor(UIColor.redColor) as! MSBColor!
            textBlock?.margins = MSBPageMargins(left: 5, top: 2, right: 5, bottom: 2)
            
            let button = MSBPageTextButton(rect: MSBPageRect(x: 0, y: 0, width: 200, height: 40))
            button?.elementId = 11
            button?.horizontalAlignment = MSBPageHorizontalAlignment.center
            //            button?.pressedColor = MSBColor.colorWithUIColor(UIColor.purpleColor) as! MSBColor!
            button?.margins = MSBPageMargins(left: 5, top: 2, right: 5, bottom: 2)
            
            let flowList = MSBPageFlowPanel(rect: MSBPageRect(x: 15, y: 0, width: 230, height: 105))
            flowList?.addElement(textBlock)
            flowList?.addElement(button)
            
            let page = MSBPageLayout()
            page.root = flowList
            tile?.pageLayouts.add(page)
//            print (String(describing: tile!))
            
            client.tileManager.add(tile!, completionHandler: { (error) in
                
                guard let msbError = error as? NSError! else {}
                
                if error == nil || MSBErrorType(rawValue: msbError.code) == (MSBErrorType.tileAlreadyExist){
                    print("Creating page...")
                    
                    let pageID = UUID(uuidString: "1234BA9F-12FD-47A5-83A9-E7270A43BB99")
                    
                    let pageValues = [try?MSBPageTextButtonData(elementId: 11, text: "No"), try?MSBPageTextBlockData(elementId: 10, text: "Question?")]
                    
                    let page = MSBPageData(id: pageID, layoutIndex: 0, value: pageValues)
                    
                    client.tileManager.setPages([page], tileId: tile!.tileId, completionHandler: { (error) in
                        if error != nil {
                            print("Error setting page: \(error)")
                        } else {
                            print("Successfully Finished!!!")
                            print("You can press the button on the D Tile to observe Tile Events,")
                            print("or remove the tile via Microsoft Health App.")
                        }
                    })
                    
                    client.notificationManager.sendMessage(withTileID: tile!.tileId!, title: "Activity Monitor", body: "Hi, may I ask you a question?", timeStamp: Date(), flags: .showDialog) { error in
                        if (error != nil) {
                            print ("error in sending notification " + String(describing: error))
                        }
                    }
                    
                    if #available(iOS 10.0, *) {
                        _ = Timer.scheduledTimer(withTimeInterval: 10, repeats: false, block: { (timer) in
                            client.tileManager.removePages(inTile: tile!.tileId!, completionHandler: { (error) in
                                if (error != nil) {
                                    print (String(describing: error))
                                }
                                print("timer has ended")
                                
                                if self.askUserFlag == true {
                                    self.askUser()
                                }
                                else {
                                    print ("The user is busy")
                                }
                                
                                self.askUserFlag = true
                            })
                        })
                    } else {
                        // Fallback on earlier versions
                    }
                }
                else {
                    print (error!)
                }
            })
        }
        else {
            print("Band is not connected. Please wait....")
        }
        
        print("button has been added")
    }
    
    func MBandOnConnect() {
        print ("button pressed")
        if let client = self.client {
            print("inside client")
            if client.isDeviceConnected == false {
                print("Band is not connected. Please wait....")
                return
            }
            print("Button tile...")
            let tileName = "D tile"
            let titleIcon = try? MSBIcon(uiImage: UIImage(named:"D.png"))
            let smallIcon = try? MSBIcon(uiImage: UIImage(named:"Dd.png"))
            
            let tile = try? MSBTile(id: tileID! as UUID, name: tileName, tileIcon: titleIcon, smallIcon: smallIcon)
            tile?.isBadgingEnabled
            
            globalTile = tile!
            
            client.tileManager.add(tile!, completionHandler: { (error) in
                
                guard let msbError = error as? NSError! else {}
                
                if error == nil || MSBErrorType(rawValue: msbError.code) == (MSBErrorType.tileAlreadyExist){
                    print("Creating page...")
                    
                    client.notificationManager.sendMessage(withTileID: tile!.tileId!, title: "Activity Monitor", body: "MicrosoftBand Ready", timeStamp: Date(), flags: .showDialog) { error in
                        if (error != nil) {
                            print ("error in sending notification " + String(describing: error))
                        }
                    }
                    
                    if #available(iOS 10.0, *) {
                        _ = Timer.scheduledTimer(withTimeInterval: 1, repeats: false, block: { (timer) in
                            client.tileManager.removePages(inTile: tile!.tileId!, completionHandler: { (error) in
                                if (error != nil) {
                                    print (String(describing: error))
                                }
                                print("timer has ended")
                            })
                        })
                    } else {
                        // Fallback on earlier versions
                    }
                }
                else {
                    print (error!)
                }
            })
        }
        else {
            print("Band is not connected. Please wait....")
        }
        
        print("button has been added")
    }
    
    func promptUser() {
        self.userInput = ""
        
        if !self.synth.isSpeaking {

            do {
                try audioSession.setCategory(AVAudioSessionCategoryPlayAndRecord, with: [.allowBluetooth])
            } catch {
                fatalError("Error Setting Up Audio Session")
            }
            
            print ("You can say something now!")
            client?.notificationManager.vibrate(with: MSBNotificationVibrationType.twoToneHigh) { error in
                if (error != nil) {
                    print(error)
                }
            }
            
            self.textView.text = "You can say something now"
            audioData = NSMutableData()
            
            _ = AudioController.sharedInstance.prepare(specifiedSampleRate: Int(SAMPLE_RATE))
            _ = AudioController.sharedInstance.start()
            
            if #available(iOS 10.0, *) {
                self.timerForRecording = Timer.scheduledTimer(withTimeInterval: 20, repeats: false, block: { (timer) in
                    self.stopAudioTemp()
                    print("timer Stopped")
                    do {
                        if self.userInput == "" {
                            print("no response from the user")
                            self.userInput = "No Response From User"
                            self.textView.text = self.userInput
                            try self.audioSession.setCategory(AVAudioSessionCategoryPlayback)
                            self.backgroundTask.startBackgroundTask()
                            self.addPostFunc()
                            print("after 20 seconds")
                        }
                        
//                        self.userInput = ""
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
                            print ("processing data")
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
                            print("done recording")
                            strongSelf.doneWithRecording()
                        }
                    }
            })
            self.audioData = NSMutableData()
        }
    }
    
    func speechDidFinish() {
        print ("prompting user")
        self.promptUser()
    }
    
    func doneWithRecording() {
        self.timerForRecording.invalidate()
        self.stopAudioTemp()
        do {
            print ("finished recording")
            try audioSession.setCategory(AVAudioSessionCategoryPlayback)
            
            semaphore.wait()
            semaphore.signal()
            print ("need to check: " + String(needToCheckInput))
            if needToCheckInput {
                print ("need to check: " + String(needToCheckInput) + " inside")
                
                // callback hell to ask the user again if they can't confirm what they said

                if self.userInput == "yes" {
                    print ("Post confirmed")
                    self.userInput = firstResponse
                    self.addPostFunc()
                    self.client?.notificationManager.sendMessage(withTileID: self.globalTile.tileId!, title: "Activity Monitor", body: "Response recieved", timeStamp: Date(), flags: .showDialog) { error in
                        if (error != nil) {
                            print ("error in sending notification " + String(describing: error))
                        }
                    }
                    
                    if #available(iOS 10.0, *) {
                        _ = Timer.scheduledTimer(withTimeInterval: 5, repeats: false, block: { (timer) in
                            self.client?.tileManager.removePages(inTile: self.globalTile.tileId!, completionHandler: { (error) in
                                if (error != nil) {
                                    print (String(describing: error))
                                }
                                print("deleted notification for uploading response")
                            })
                        })
                    } else {
                        // Fallback on earlier versions
                    }
                    
                    self.backgroundTask.startBackgroundTask()
                }
                else if self.userInput == "no"{
                    self.askUserAgain()
                }
                else {
                    checkUserInput()
                }
                
                print ("uploaded: " + self.userInput)
            }
            
        } catch {
            // handle errors
            print ("error happened in doneWithRecoring")
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
    
    // MARK - Client Manager Delegates
    func clientManager(_ clientManager: MSBClientManager!, clientDidConnect client: MSBClient!) {
        print("Band connected.")
        MBandOnConnect()
    }
    
    func clientManager(_ clientManager: MSBClientManager!, clientDidDisconnect client: MSBClient!) {
        print("Band disconnected.")
    }
    
    func clientManager(_ clientManager: MSBClientManager!, client: MSBClient!, didFailToConnectWithError error: Error!) {
        print("Failed to connect to Band.")
    }
    
    // MARK - Client Tile Delegate
    func client(_ client: MSBClient!, buttonDidPress event: MSBTileButtonEvent!) {
        print("\(event.description)")
        print("button pressed")
        client.tileManager.removePages(inTile: tileID! as UUID, completionHandler: { (error) in
            if (error != nil) {
                print (String(describing: error))
            }
        })
        self.userInput = "No Response"
        self.addPostFunc()
        
        self.askUserFlag = false
    }
    
    @objc(client:tileDidOpen:) func client(_ client: MSBClient!, tileDidOpen  event: MSBTileEvent!) {
        print("\(event.description)")
    }
    
    func client(_ client: MSBClient!, tileDidClose event: MSBTileEvent!) {
        print("\(event.description)")
    }
    
    func isConnectedToNetwork() -> Bool {
        var zeroAddress = sockaddr_in(sin_len: 0, sin_family: 0, sin_port: 0, sin_addr: in_addr(s_addr: 0), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        zeroAddress.sin_len = UInt8(MemoryLayout.size(ofValue: zeroAddress))
        zeroAddress.sin_family = sa_family_t(AF_INET)
        
        let defaultRouteReachability = withUnsafePointer(to: &zeroAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {zeroSockAddress in
                SCNetworkReachabilityCreateWithAddress(nil, zeroSockAddress)
            }
        }
        
        var flags: SCNetworkReachabilityFlags = SCNetworkReachabilityFlags(rawValue: 0)
        if SCNetworkReachabilityGetFlags(defaultRouteReachability!, &flags) == false {
            return false
        }
        
        /* Only Working for WIFI
         let isReachable = flags == .reachable
         let needsConnection = flags == .connectionRequired
         
         return isReachable && !needsConnection
         */
        
        // Working for Cellular and WIFI
        let isReachable = (flags.rawValue & UInt32(kSCNetworkFlagsReachable)) != 0
        let needsConnection = (flags.rawValue & UInt32(kSCNetworkFlagsConnectionRequired)) != 0
        let ret = (isReachable && !needsConnection)
        
        return ret
    }
}
