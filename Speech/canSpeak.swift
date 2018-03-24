//
//  canSpeak.swift
//  Speech
//
//  Created by Ka Tai Ho on 12/16/17.
//  Copyright © 2017 Google. All rights reserved.
//

import Foundation
import AVFoundation

protocol CanSpeakDelegate {
    func speechDidFinish()
}

class CanSpeak: NSObject, AVSpeechSynthesizerDelegate {
    
    let voices = AVSpeechSynthesisVoice.speechVoices()
    let voiceSynth = AVSpeechSynthesizer()
    var voiceToUse: AVSpeechSynthesisVoice?
    let audioSession = AVAudioSession.sharedInstance()
    
    var delegate: CanSpeakDelegate!
    
    override init(){
        super.init()
        if let v = UserDefaults.standard.object(forKey: "voice") as? String {
            voiceToUse = AVSpeechSynthesisVoice.speechVoices().filter({ $0.name == v }).first
        }
        else {
            voiceToUse = AVSpeechSynthesisVoice.speechVoices().filter({ $0.name == "Karen" }).first
        }
//        voiceToUse = AVSpeechSynthesisVoice.speechVoices().filter({ $0.name == "Monica" }).first
        self.voiceSynth.delegate = self
    }
    
    func testVoice (voice: String, phrase: String, speed: Float) {
        voiceToUse = AVSpeechSynthesisVoice.speechVoices().filter({ $0.name == voice }).first
        
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = voiceToUse
        utterance.rate = speed
        voiceSynth.speak(utterance)
    }
    
    func sayThis(_ phrase: String, speed: Float){
        if let v = UserDefaults.standard.object(forKey: "voice") as? String {
            voiceToUse = AVSpeechSynthesisVoice.speechVoices().filter({ $0.name == v }).first
        }
        
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = voiceToUse
        utterance.rate = speed
        voiceSynth.speak(utterance)
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        self.delegate.speechDidFinish()
    }
}
