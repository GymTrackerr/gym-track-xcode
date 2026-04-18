//
//  User.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-03.
//

import Foundation
import SwiftData

@Model
final class User {
    var id: UUID = UUID()
    var name: String
    var timestamp: Date
    var lastLogin: Date
    var soft_deleted: Bool = false
    var syncMetaId: UUID? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var active: Bool = true
    var isDemo: Bool = false
    var allowHealthAccess: Bool = false
    var remoteAccountId: String? = nil
    var remoteSyncEnabled: Bool = true
    var exerciseCatalogEnabled: Bool = false
    
    var defaultTimer: Int = 90
    var showNutritionTab: Bool = true
    var preferredHealthHistorySyncRangeRaw: String?

    // Phase 9 optional timer feedback settings (non-destructive)
    var timerNotificationsEnabled: Bool?
    var timerFinishedNotificationEnabled: Bool?
    var awayTooLongEnabled: Bool?
    var awayTooLongMinutes: Int?
    var countdownHapticsEnabled: Bool?
    var hapticAt30: Bool?
    var hapticAt15: Bool?
    var hapticAt5: Bool?
    
    init(name: String, isDemo: Bool = false) {
        let timestamp = Date()
        self.name = name
        self.isDemo = isDemo
        self.remoteSyncEnabled = !isDemo
        self.timestamp = timestamp
        self.lastLogin = timestamp
        self.createdAt = timestamp
        self.updatedAt = timestamp
    }
}
