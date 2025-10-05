//
//  Set.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import Foundation
import SwiftData

@Model
final class Set {
    var id: UUID = UUID()
    var order: Int
//    var type: Set_Types
    var notes: String?
    var timestamp: Date

    var sessionExercise: SessionExercise
    var session_exercise_id: UUID { sessionExercise.id }

    init(order: Int, sessionExercise: SessionExercise, notes: String? = nil) {
        self.order = order
        self.notes = notes
        self.timestamp = Date()
        
        self.sessionExercise = sessionExercise
    }
}
