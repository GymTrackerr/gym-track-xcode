//
//  TimerActivityAttributes.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-12-07.
//

import ActivityKit
import SwiftUI
import Foundation

struct TimerActivityAttributes: ActivityAttributes, Codable {
    public struct ContentState: Codable, Hashable {
        var remainingSeconds: Int
        var isPaused: Bool
        var pausedAtSeconds: Int = 0  // Seconds remaining when paused
        var lastUpdateTime: Date = Date()  // When this state was last updated from the app
        var timerId: String = ""  // Optional correlation id from the app-side timer
    }

    var title: String
    var totalLength: Int // for displaying progress ring
}
