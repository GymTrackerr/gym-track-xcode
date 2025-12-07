//
//  TimerService+LiveActivity.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-12-07.
//

import ActivityKit
import Foundation

extension TimerService {
    // Start a live activity for the current timer
    func startLiveActivity() {
        guard let timer = self.timer else {
            print("Cannot start live activity - no timer exists")
            return
        }
        // print("Starting live activity for timer: \(timer.id.uuidString)")
        LiveActivityManager.shared.start(length: timer.timerLength, timerId: timer.id.uuidString)
    }
    
    // Update the live activity with current timer state
    func updateLiveActivity() {
        guard let timer = timer else { return }
        LiveActivityManager.shared.update(
            remainingSeconds: remainingTime ?? displayedTime,
            totalLength: timer.timerLength,
            isPaused: timer.isPaused
        )
    }
    
    // End the live activity
    func endLiveActivity(after seconds: UInt64 = 0) {
        LiveActivityManager.shared.end(after: seconds)
    }
}
