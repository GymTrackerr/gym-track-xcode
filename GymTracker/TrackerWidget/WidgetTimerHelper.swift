//
//  WidgetTimerHelper.swift
//  TrackerWidget
//
//  Created by Daniel Kravec on 2025-12-07.
//

// TODO, update so not hacky with the get timer method

import ActivityKit
import Combine
import WidgetKit

// Shared helper for live activity timer views
struct WidgetTimerHelper {
    let context: ActivityViewContext<TimerActivityAttributes>
    
    var remainingSeconds: Int {
        // Use activity state for reliable countdown
        if context.state.isPaused {
            return context.state.pausedAtSeconds
        }
        
        let elapsedSinceUpdate = Int(Date().timeIntervalSince(context.state.lastUpdateTime))
        let remaining = context.state.remainingSeconds - elapsedSinceUpdate
        return max(remaining, 0)
    }
    
    func getTimer(isPaused: Bool) -> Timer.TimerPublisher {
        // Only publish timer events if not paused
        if isPaused {
            return Timer.publish(every: 999999, on: .main, in: .common) // Never fires
        } else {
            return Timer.publish(every: 0.5, on: .main, in: .common)
        }
    }
}
