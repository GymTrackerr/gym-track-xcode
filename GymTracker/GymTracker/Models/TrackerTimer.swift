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
}
