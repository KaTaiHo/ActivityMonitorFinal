//
//  backgroundTask.swift
//  ActivityMonitor
//
//  Created by Ka Tai Ho on 10/9/17.
//  Copyright © 2017 SDLtest. All rights reserved.
//

import AVFoundation
import Speech

class BackgroundTask {
    var player = AVAudioPlayer()
    var timer = Timer()
    
    func startBackgroundTask() {
        NotificationCenter.default.addObserver(self, selector: #selector(interuptedAudio), name: NSNotification.Name.AVAudioSessionInterruption, object: AVAudioSession.sharedInstance())
        self.playAudio()
    }
    
    func stopBackgroundTask() {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVAudioSessionInterruption, object: nil)
        player.stop()
    }
    
    func pauseBackgroundTask() {
        player.pause()
        do {
//            try AVAudioSession.sharedInstance().setActive(false)
        } catch { print("error in backgroundTask" + error.localizedDescription) }
    }
    
    @objc fileprivate func interuptedAudio(_ notification: Notification) {
        if notification.name == NSNotification.Name.AVAudioSessionInterruption && notification.userInfo != nil {
            var info = notification.userInfo!
            var intValue = 0
            (info[AVAudioSessionInterruptionTypeKey]! as AnyObject).getValue(&intValue)
            if intValue == 1 { playAudio() }
        }
    }
    
    fileprivate func playAudio() {
        do {
            let bundle = Bundle.main.path(forResource: "silence", ofType: "mp3")
            let alertSound = URL(fileURLWithPath: bundle!)
            try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback, with:AVAudioSessionCategoryOptions.mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            try self.player = AVAudioPlayer(contentsOf: alertSound)
            self.player.numberOfLoops = -1
            self.player.volume = 1
            self.player.prepareToPlay()
            self.player.play()
        } catch { print("error in backgroundTask" + error.localizedDescription) }
    }
}
