//
//  SharedTimerModels.swift
//  GymTracker
//
//  Created by OpenAI Codex on 2026-04-14.
//

import Foundation

struct SharedTimerState: Codable {
    let timerId: String
    let remainingSeconds: Int
    let totalLength: Int
    let isPaused: Bool
    let lastUpdateTime: TimeInterval
}

struct WatchTimerSnapshot: Identifiable, Codable {
    let id: String
    let startTime: Date?
    let elapsedTime: Int
    let timerLength: Int
    let isPaused: Bool
    let createdAt: Date
    let updatedAt: Date
}

struct SharedTimerRuntimeSnapshot {
    let timerId: String?
    let displayedSeconds: Int
    let remainingSeconds: Int?
    let totalLength: Int
    let isPaused: Bool
    let hasTimer: Bool
    let lastUpdateTime: Date

    var primarySeconds: Int {
        remainingSeconds ?? displayedSeconds
    }

    var progress: Double {
        guard let remainingSeconds, totalLength > 0 else {
            return hasTimer ? 1 : 0
        }

        return max(min(Double(remainingSeconds) / Double(totalLength), 1), 0)
    }

    var countdownEndDate: Date? {
        guard let remainingSeconds, isPaused == false else { return nil }
        return lastUpdateTime.addingTimeInterval(TimeInterval(max(remainingSeconds, 0)))
    }
}
