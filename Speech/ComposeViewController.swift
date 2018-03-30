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

let SAMPLE_RATE = 16000
//let SAMPLE_RATE = 44100.0


class ComposeViewController : UIViewController, AudioControllerDelegate, CanSpeakDelegate, ConnectionDelegate, MSBClientManagerDelegate, MSBClientTileDelegate, AVAudioRecorderDelegate{
    
    @IBOutlet weak var liveLabel: UILabel!
    @IBOutlet weak var textView: UITextView!
    @IBOutlet weak var startButton: UIButton!
    @IBOutlet weak var pauseButton: UIButton!
    @IBOutlet weak var debugLabel: UILabel!
    @IBOutlet weak var currentSettingsLabel: UILabel!
    let questions = ["Hello, What are you doing right now?", "Hello, Who are you with right now?", "Hello, How would you describe your mood right now?", "Hello, What was the last thing you ate?", "Hello, Are you happy right now?", "Hello, Are you tired right now?",
        "Hello, How stressed are you right now?"]
    
    var userId: String?
    var ref: DatabaseReference?
    var askInterval = 120
    var timerForRecording: Timer?
    weak var client: MSBClient?
    let tileID = NSUUID(uuidString: "CDBDBA9F-12FD-47A5-8453-E7270A43BB99")
    
    var debug = false
    
    var audioData: NSMutableData!
    var textToSpeechTimerBackground = Timer()
    var backgroundTask = BackgroundTask()
    var audioEngine = AVAudioEngine()
    var userInput = String()
    var sessionStarted = false
    var clockTimer = 0
    
    var killThisSession = false
    let canSpeak = CanSpeak()
    let audioSession = AVAudioSession.sharedInstance()
    var firstResponse = ""
    var needToCheckInput = false
    var askUserFlag = true
    var globalTile = MSBTile()
    
    var currentQuestion = String()
    
    var sessionSemaphore = DispatchSemaphore(value: 0)
    var recordingSemaphore = DispatchSemaphore(value: 0)
    
    var bluetoothConnectSemaphore = DispatchSemaphore(value: 0)
    
    var noInternetString = ""
    // for extension

    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.canSpeak.delegate = self
        AudioController.sharedInstance.delegate = self
        ref = Database.database().reference()
        userId = Auth.auth().currentUser?.uid
        textView.isEditable = false
        setupSessionForRecording()
        startButton.alpha = 0.5
        pauseButton.alpha = 0.5
        
        startButton.layer.cornerRadius = 10;
        startButton.clipsToBounds = true;
        
        pauseButton.layer.cornerRadius = 10;
        pauseButton.clipsToBounds = true;
        
        startButton.isUserInteractionEnabled = false
        pauseButton.isUserInteractionEnabled = false
        
        MSBClientManager.shared().delegate = self
//        liveLabel.isHidden = true
        liveLabel.text = "Offline"
        
        if !debug {
            debugLabel.isHidden = true
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        setupSessionForRecording()
        if let client = MSBClientManager.shared().attachedClients().first as? MSBClient {
            self.client = client
            // 2. Set Tile Event Delegate
            client.tileDelegate = self;
            
            if client.isDeviceConnected && !self.sessionStarted{
                startButton.alpha = 1
                startButton.isUserInteractionEnabled = true
            }
            else {
                MSBClientManager.shared().connect(self.client)
                print("Please wait. Connecting to Band...")
            }
        } else {
            print("Failed! No Bands attached.")
        }
        
        var currentSettingsString = String()

        if let currentVoice = UserDefaults.standard.string(forKey: "voice") {
            currentSettingsString = currentVoice
        }
        else {
            currentSettingsString = "Karen"
        }
        
        if let value = UserDefaults.standard.object(forKey: "userTimeInterval") as? Int {
            currentSettingsString = currentSettingsString + " interval " + String(value/60) + " minutes"
            askInterval = value
        }
        else {
            currentSettingsString = currentSettingsString + " interval: " + String(askInterval/60) + " minutes"
        }
        
        currentSettingsLabel.text = currentSettingsString
    }
    
    @IBAction func recordAudio(_ sender: NSObject) {
        killThisSession = false
        if client?.isDeviceConnected == true {
            self.userInput = "user started session"
            self.addPostFunc()
            self.userInput = ""
            print("button pressed")
            SpeechRecognitionService.sharedInstance.sampleRate = Int(SAMPLE_RATE)
            
            backgroundTask.startBackgroundTask()
            //        checkUserInput()
            MBSaskUser()
            
            // get UserDefault
            if let value = UserDefaults.standard.object(forKey: "userTimeInterval") as? Int {
                print("userDefault picked time interval of " + String(value))
                askInterval = value
            }
            
            textToSpeechTimerBackground = Timer.scheduledTimer(timeInterval: TimeInterval(askInterval), target: self, selector: #selector(self.MBSaskUser), userInfo: nil, repeats: true)
            
//            _ = Timer.scheduledTimer(timeInterval: 30, target: self, selector: #selector(self.clockTick), userInfo: nil, repeats: true)
            self.sessionStarted = true
            liveLabel.text = "Online"
            liveLabel.isHidden = false
            liveLabel.textColor = UIColor.red
            startButton.alpha = 0.5
            startButton.isUserInteractionEnabled = false
            pauseButton.alpha = 1
            pauseButton.isUserInteractionEnabled = true
            sessionSemaphore.signal()
        }
        else {
            self.textView.text = "Microsoft band is not connected please check"
        }
        // tell the user to wait for the band to connect TODO
    }
    
    func clockTick() {
        clockTimer = clockTimer + 30
        let timestring = (String(clockTimer / 60) + " minutes and " +  String(clockTimer % 60) + " seconds have passed")
        
        print (timestring)
        debugLabel.text = timestring
    }
    
    func MBSaskUser() {
        backgroundTask.stopBackgroundTask()
        backgroundTask.startBackgroundTask()
        
        if self.isConnectedToNetwork() {
            if self.noInternetString != "" {
                self.userInput = self.noInternetString
                addPostFunc()
                self.userInput = ""
                self.noInternetString = ""
            }
            if !killThisSession {
                MBandSetUp()
            }
        }
        else {
            print("The user is not connected to the internet")
            self.textView.text = "The user is not connected to the internet"
            self.noInternetString += "There was no internet the last session "
        }
    }
    
    func setupSessionForRecording() {
        do {
            try audioSession.setCategory(AVAudioSessionCategoryRecord, with: [.allowBluetooth])
            
            // testing the following code
//            try audioSession.setMode(AVAudioSessionModeDefault)
//            try audioSession.setCategory(AVAudioSessionCategoryPlayback)
//            try audioSession.setActive(true, with: .notifyOthersOnDeactivation)
//            try audioSession.setActive(true, with: .notifyOthersOnDeactivation)
        } catch {
            fatalError("Error Setting Up Audio Session")
        }
        
        print ("INPUT LIST:")
        var hasBand = false
        
        var deviceName = "LG HBSW120"
        for availableInput in audioSession.availableInputs! {
            if availableInput.portName == deviceName {
                do {
                    try audioSession.setPreferredInput(availableInput)
                    print ("found and setting the port to: " + String(describing: availableInput))
                    hasBand = true
                    break;
                }
                catch {
                    fatalError("Error Setting Up Audio Session")
                }
            }
        }
        
        var errorString = "Warning:\n "
        var errorFlag = false
        
        if hasBand == false {
            errorString += " -The LG Band is not connected\n"
            errorFlag = true
        }
        
        if isConnectedToNetwork() == false {
            errorString += " -no wifi/LTE\n"
            errorFlag = true
        }
        
        errorString += " *****Please make sure you fix this before starting a session*****\n"

        if MSBClientManager.shared().attachedClients().count == 0 {
            errorString += " -Microsoft band is not connected and the session cannot start without the band. Please connect and restart the app."
            errorFlag = true
        }
        
        if errorFlag {
            self.textView.text = errorString
        }
    }
    
    func askUser() {
//        backgroundTask.pauseBackgroundTask()
        let askString = questions[Int(arc4random_uniform(UInt32(questions.count)))]
        self.currentQuestion = askString
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(AVAudioSessionCategoryPlayback)
            try audioSession.setMode(AVAudioSessionModeDefault)
            try audioSession.setActive(true, with: .notifyOthersOnDeactivation)
        }
        catch {
            
        }
        
        self.canSpeak.sayThis(askString, speed: 0.5)
    }
    
    func askUserConfirmation() {
//        backgroundTask.pauseBackgroundTask()
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(AVAudioSessionCategoryPlayback)
            try audioSession.setMode(AVAudioSessionModeDefault)
            try audioSession.setActive(true, with: .notifyOthersOnDeactivation)
        }
        catch {
            
        }
        
        self.canSpeak.sayThis("Could you please confirm with yes or no?", speed: 0.5)
    }
    
    func AskUserAgain() {
//        backgroundTask.pauseBackgroundTask()
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(AVAudioSessionCategoryPlayback)
            try audioSession.setMode(AVAudioSessionModeDefault)
            try audioSession.setActive(true, with: .notifyOthersOnDeactivation)
        }
        catch {
            
        }
        
        self.canSpeak.sayThis("Could you please repeat what you said?", speed: 0.5)
    }
    
    func checkUserInput(){
//        backgroundTask.pauseBackgroundTask()
        firstResponse = self.userInput
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(AVAudioSessionCategoryPlayback)
            try audioSession.setMode(AVAudioSessionModeDefault)
            try audioSession.setActive(true, with: .notifyOthersOnDeactivation)
        }
        catch {
            
        }
        
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
            recordingSemaphore.wait()
            backgroundTask.stopBackgroundTask()
            killThisSession = true
            
            textToSpeechTimerBackground.invalidate()
            liveLabel.isHidden = true
        }
        
        self.sessionStarted = false
        presentingViewController?.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func stopAudio(_ sender: NSObject) {
        sessionSemaphore.wait()
        print("stopping the audio")
        
        self.userInput = "user stopped the session"
        self.addPostFunc()
        self.userInput = ""

        if SpeechRecognitionService.sharedInstance.isStreaming() {
            SpeechRecognitionService.sharedInstance.stopStreaming()
             _ = AudioController.sharedInstance.stop()
        }
        
        killThisSession = true
        backgroundTask.stopBackgroundTask()
        
        textToSpeechTimerBackground.invalidate()
        timerForRecording?.invalidate()
        
        liveLabel.isHidden = false
        liveLabel.textColor = UIColor.gray
        liveLabel.text = "Offline"
        self.sessionStarted = false
        

        startButton.alpha = 1
        startButton.isUserInteractionEnabled = true
        pauseButton.alpha = 0.5
        pauseButton.isUserInteractionEnabled = false
    }
    
    func MBandSetUp() {
        if let client = self.client {
            print("inside client")
            if client.isDeviceConnected == false {
                print("Band is not connected. Please wait....")
                MSBClientManager.shared().connect(self.client)
                bluetoothConnectSemaphore.wait()
//                startButton.alpha = 1
//                startButton.isUserInteractionEnabled = true
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
                            print("Error setting page: \(error!)")
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
                                
                                if self.askUserFlag == true && !self.killThisSession{
                                    self.needToCheckInput = false
                                    self.askUser()
                                }
                                else {
                                    print ("The user is busy or they paused the session")
                                    self.backgroundTask.startBackgroundTask()
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
        bluetoothConnectSemaphore.signal()
        if !sessionStarted {
            startButton.isUserInteractionEnabled = true
            startButton.alpha = 1
        }
    }
    
    func promptUser() {
        self.userInput = ""
        
        print ("You can say something now!")
        
        self.textView.text = "You can say something now"
        audioData = NSMutableData()
        
        _ = AudioController.sharedInstance.prepare(specifiedSampleRate: Int(SAMPLE_RATE))
        _ = AudioController.sharedInstance.start()
        
        client?.notificationManager.vibrate(with: MSBNotificationVibrationType.twoToneHigh) { error in
            if (error != nil) {
                print(error)
            }
        }
        
        if #available(iOS 10.0, *) {
            self.timerForRecording = Timer.scheduledTimer(withTimeInterval: 40, repeats: false, block: { (timer) in
                self.stopAudioTemp()
                self.recordingSemaphore.wait()
                print("timer Stopped")
                do {
                    if self.userInput == "" {
                        print("no response from the user")
                        self.userInput = "The device did not pick up any sound or the environment is too noisy"
                        self.textView.text = self.userInput
                        try self.audioSession.setCategory(AVAudioSessionCategoryPlayback)
                        try self.audioSession.setMode(AVAudioSessionModeDefault)

                        self.addPostFunc()
                        print("after 40 seconds")
                        self.backgroundTask.startBackgroundTask()
                    }
                } catch {
                    // handle errors
                }
                print("timer has ended")

            })
        } else {
            // Fallback on earlier versions
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
        recordingSemaphore.signal()
    }
    
    func processSampleData(_ data: Data) -> Void {
        if killThisSession {
            return
        }
        
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
                        self?.addPostFunc()
                        self?.userInput = "error"
                        self?.doneWithRecording()
                        return
                    } else if let response = response {
                        var finished = false
                        
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
        
        do {
            // stop session when u finish asking the user
        }
        catch {
            
        }
        
        self.promptUser()
    }
    
    func doneWithRecording() {
        self.timerForRecording?.invalidate()
        self.timerForRecording = nil
        
        self.stopAudioTemp()
        
        self.recordingSemaphore.wait()
        
        do {
            print ("finished recording")
            // stop session from recording audio
            
            print ("need to check: " + String(needToCheckInput))
//            if needToCheckInput {
                print ("need to check: " + String(needToCheckInput) + " inside")
                
                // callback hell to ask the user again if they can't confirm what they said
                
                if self.userInput == "error" {
                    self.client?.notificationManager.sendMessage(withTileID: self.globalTile.tileId!, title: "Activity Monitor", body: "Session Ended", timeStamp: Date(), flags: .showDialog) { error in
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
                    }
                    else {
                        // Fallback on earlier versions
                    }
                    self.needToCheckInput = false
                    self.backgroundTask.startBackgroundTask()
                }
                else if (self.userInput == "yes" || self.userInput == "yeah" || self.userInput == "correct") && needToCheckInput {
                    print ("Post confirmed")
                    self.userInput = currentQuestion + ": " + firstResponse
                    self.addPostFunc()
                    
                    self.textView.text = "Upload success!"

                    client?.notificationManager.vibrate(with: MSBNotificationVibrationType.twoToneHigh) { error in
                        if (error != nil) {
                            print(error)
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
                    
                    self.needToCheckInput = false
                    
                    self.backgroundTask.startBackgroundTask()
                }
                else if (self.userInput == "no" || self.userInput == "nah") && needToCheckInput {
                    needToCheckInput = false
                    AskUserAgain()
                }
                else if needToCheckInput == false{
                    needToCheckInput = true
                    checkUserInput()
                }
                else {
                    
                    askUserConfirmation()
                }
            
                print ("uploaded: " + self.userInput)
//            }
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
    }
    
    @objc(client:tileDidOpen:) func client(_ client: MSBClient!, tileDidOpen  event: MSBTileEvent!) {
        print("\(event.description)")
        print("\(event.description)")
        print("tile opened")
        
        client.tileManager.removePages(inTile: tileID! as UUID, completionHandler: { (error) in
            if (error != nil) {
                print (String(describing: error))
            }
        })
        
        self.userInput = "No Response"
        self.addPostFunc()
        self.askUserFlag = false
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
        
        // Working for Cellular and WIFI
        let isReachable = (flags.rawValue & UInt32(kSCNetworkFlagsReachable)) != 0
        let needsConnection = (flags.rawValue & UInt32(kSCNetworkFlagsConnectionRequired)) != 0
        let ret = (isReachable && !needsConnection)
        
        return ret
    }
}
