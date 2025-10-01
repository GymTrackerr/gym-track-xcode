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
    var exercise_id: UUID
    var workout_id: UUID
    var set_type: Int?
    var order: Int
    var notes: String?
    
    init(exercise_id: UUID, workout_id: UUID, set_type: Int? = nil, order: Int, notes: String? = nil) {
        self.exercise_id = exercise_id
        self.workout_id = workout_id
        self.set_type = set_type
        self.order = order
        self.notes = notes
    }
}
