//
//  ExerciseSplitDay.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-02.
//

import Foundation
import SwiftData

// join table
@Model
final class ExerciseSplitDay {
    var id: UUID = UUID()
    var order: Int
    
    var routine: Routine
    
    var exercise: Exercise

    var routine_id: UUID { routine.id }
    var exercise_id: UUID { exercise.id }

    init(order: Int, routine: Routine, exercise: Exercise) {
        self.order = order
        self.routine = routine
        self.exercise = exercise
    }
}
