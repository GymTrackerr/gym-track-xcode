//
//  TrackerTimer.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-12-06.
//

import Foundation
import SwiftData

@Model
final class TrackerTimer {
    @Attribute(.unique) var id: UUID = UUID()
    var startTime: Date?
    var elapsedTime: Int
    var timerLength: Int // 0 = count-up
    var isPaused: Bool
    var createdAt: Date
    var updatedAt: Date
    
    init(
        startTime: Date? = nil,
        elapsedTime: Int = 0,
        timerLength: Int = 0,
        isPaused: Bool = true
    ) {
        self.startTime = startTime
        self.elapsedTime = elapsedTime
        self.timerLength = timerLength
        self.isPaused = isPaused
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    func toDTO() -> TrackerTimerDTO {
        TrackerTimerDTO(
            id: id.uuidString,
            startTime: startTime,
            elapsedTime: elapsedTime,
            timerLength: timerLength,
            isPaused: isPaused,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct TrackerTimerDTO: Identifiable, Codable {
    let id: String
    let startTime: Date?
    let elapsedTime: Int
    let timerLength: Int
    let isPaused: Bool
    let createdAt: Date
    let updatedAt: Date
    
    func apply(to timer: TrackerTimer) {
        timer.id = UUID(uuidString: id) ?? UUID()
        if let startTime = startTime {
            timer.startTime = startTime
        }
        timer.elapsedTime = elapsedTime
        timer.timerLength = timerLength
        timer.isPaused = isPaused
        timer.createdAt = createdAt
        timer.updatedAt = updatedAt
    }
}

enum TimerLifecycleStatus: String, Codable {
    case running
    case paused
    case completed
    case cancelled
}

enum TimerLifecycleEventType: String, Codable {
    case started
    case paused
    case resumed
    case adjusted
    case cancelled
    case completed
    case appBackgrounded
    case appForegrounded
}

struct TimerLifecycleEvent: Codable {
    let eventType: TimerLifecycleEventType
    let timerId: String
    let status: TimerLifecycleStatus
    let remainingDurationSeconds: Int
    let totalDurationSeconds: Int
    let effectiveAt: Date
    let completedAt: Date?
    let cancelledAt: Date?
}
