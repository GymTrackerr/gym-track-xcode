//
//  Workout.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import Foundation
import SwiftData

@Model
final class Session {
    var id: UUID = UUID()
    var user_id: UUID
    var timestamp: Date
    var timestampDone: Date = Date() // temporary just saving as 
    var notes: String = ""
    
    var routine: Routine?
    var routine_id: UUID? { routine?.id }
    
    @Relationship(deleteRule: .cascade)
    var sessionEntries: [SessionEntry]

    init (timestamp: Date, user_id: UUID, routine: Routine?, notes: String) {
        self.timestamp = timestamp
        self.user_id = user_id
        self.notes = notes
        self.routine = routine
        self.timestampDone = timestamp
        self.sessionEntries = []
    }
}
