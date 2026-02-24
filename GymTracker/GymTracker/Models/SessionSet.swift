//
//  Set.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import Foundation
import SwiftData

// renamed from Set to SessionSet due to reserved keyword
@Model
final class SessionSet {
    var id: UUID = UUID()
    var order: Int
//    var type: Set_Types
    var notes: String?
    var timestamp: Date

    var durationSeconds: Int? = nil
    var distance: Double? = nil
    var paceSeconds: Int? = nil
    var distanceUnitRaw: String? = nil
    var restSeconds: Int? = nil
    
    var isCompleted: Bool = false
    var isDropSet: Bool = false
    
    var sessionEntry: SessionEntry
    var session_entry_id: UUID { sessionEntry.id }

    @Relationship(deleteRule: .cascade)
    var sessionReps: [SessionRep]
    
    init(order: Int, sessionEntry: SessionEntry, notes: String? = nil) {
        self.order = order
        self.notes = notes
        self.timestamp = Date()

        self.sessionEntry = sessionEntry
        self.sessionReps = []
    }

    var distanceUnit: DistanceUnit {
        get { DistanceUnit(rawValue: distanceUnitRaw ?? "km") ?? .km }
        set { distanceUnitRaw = newValue.rawValue }
    }
}

enum DistanceUnit: String, Codable {
    case km
    case mi
}
