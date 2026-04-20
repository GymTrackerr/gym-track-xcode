//
//  Routine.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import Foundation
import SwiftData

@Model
final class Routine {
    var id: UUID = UUID()
    var user_id: UUID
    var order: Int
    var name: String
    var defaultProgressionProfileId: UUID? = nil
    var defaultProgressionProfileNameSnapshot: String? = nil
    var timestamp: Date
    var isArchived: Bool = false
    var soft_deleted: Bool = false
    var syncMetaId: UUID? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var aliases: [String] = []
    
    @Relationship(deleteRule: .cascade)
    var exerciseSplits: [ExerciseSplitDay]
    
    @Relationship(deleteRule: .nullify)
    var sessions: [Session] = []
    
    init(order: Int, name: String, user_id: UUID) {
        let timestamp = Date()
        
        self.order = order
        self.name = name
        self.user_id = user_id
        self.timestamp = timestamp
        self.createdAt = timestamp
        self.updatedAt = timestamp
        self.exerciseSplits = []
        self.sessions = []
    }
}

extension Routine: SyncTrackedRoot {
    static var syncModelType: SyncModelType { .routine }
    var syncLinkedItemId: String { id.uuidString.lowercased() }

    var syncSeedDate: Date { timestamp }

    var legacyDeleteBridgeValue: Bool? { isArchived }

    func applyLegacyDeleteBridge(_ value: Bool) {
        isArchived = value
    }
}
