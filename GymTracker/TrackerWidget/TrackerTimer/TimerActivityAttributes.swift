//
//  TimerActivityAttributes.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-12-07.
//

import ActivityKit
import SwiftUI

struct TimerActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var remainingSeconds: Int
        var isPaused: Bool
    }

    var title: String
    var totalLength: Int   // for displaying progress ring
}
