//
//  SyncModelType.swift
//  GymTracker
//
//  Created by Codex on 2026-04-15.
//

import Foundation

enum SyncModelType: Int, Codable {
    case exercise = 1
    case routine = 2
    case session = 3
    case foodItem = 4
    case mealRecipe = 5
    case nutritionLogEntry = 6
    case nutritionTarget = 7
    case healthDailySummary = 8
    case userProfile = 9
}

enum SyncMetadataState: Int, Codable {
    case pending = 1
    case syncing = 2
    case synced = 3
    case conflict = 4
    case failed = 5
}

enum SyncQueueOperation: Int, Codable {
    case create = 1
    case update = 2
    case softDelete = 3
    case restore = 4
    case hardDelete = 5
}

enum SyncQueueStatus: Int, Codable {
    case queued = 1
    case inFlight = 2
    case retryScheduled = 3
    case blocked = 4
    case deadLetter = 5
}
