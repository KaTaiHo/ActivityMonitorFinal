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

//let SAMPLE_RATE = 16000
//let SAMPLE_RATE = 44100.0

class ViewController : UIViewController, AudioControllerDelegate, CanSpeakDelegate {
    @IBOutlet weak var textView: UITextView!
    var audioData: NSMutableData!
    var textToSpeechTimerBackground = Timer()
    var backgroundTask = BackgroundTask()
    var audioEngine = AVAudioEngine()
    let synth = AVSpeechSynthesizer()
    let canSpeak = CanSpeak()
    
    var recordingFlag = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupSessionForRecording()
        self.canSpeak.delegate = self
        AudioController.sharedInstance.delegate = self
    }
    
    @IBAction func recordAudio(_ sender: NSObject) {
        backgroundTask.startBackgroundTask()
        textToSpeechTimerBackground = Timer.scheduledTimer(timeInterval: 40, target: self, selector: #selector(self.askUser), userInfo: nil, repeats: true)
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
        setupSessionForRecording()
        self.canSpeak.sayThis("Hello, What are you doing right now?")
    }
    
    func recordUser() {
        if !self.synth.isSpeaking {
            print ("You can say something now!")
            if audioEngine.isRunning {
                audioEngine.stop()
            }
            let audioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setCategory(AVAudioSessionCategoryRecord)
            } catch {
                print("an error happened in recording")
            }
            audioData = NSMutableData()
            _ = AudioController.sharedInstance.prepare(specifiedSampleRate: Int(SAMPLE_RATE))
            SpeechRecognitionService.sharedInstance.sampleRate = Int(SAMPLE_RATE)
            self.recordingFlag = true
            _ = AudioController.sharedInstance.start()
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
    
    @IBAction func stopAudio(_ sender: NSObject) {
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
                    } else if let response = response {
                        var finished = false
                        //                        print(response)
                        for result in response.resultsArray! {
                            if let result = result as? StreamingRecognitionResult {
                                if result.isFinal {
                                    finished = true
                                    let test = result.alternativesArray[0] as! SpeechRecognitionAlternative
                                    print ("data: " + String(describing: test.transcript!))
                                }
                            }
                        }
                        strongSelf.textView.text = response.description
                        
                        
                        if finished {
                            strongSelf.stopAudio(strongSelf)
                            do {
                                let audioSession = AVAudioSession.sharedInstance()
                                try audioSession.setCategory(AVAudioSessionCategoryPlayAndRecord)
                                try audioSession.setActive(false, with: .notifyOthersOnDeactivation)
                            } catch {
                                // handle errors
                            }
                            
                        }
                    }
            })
            self.audioData = NSMutableData()
        }
    }
    
    func speechDidFinish() {
        self.recordUser()
    }
}
