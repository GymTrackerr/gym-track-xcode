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
    
    var splitDay: SplitDay
    var exercise: Exercise

    var split_day_id: UUID { splitDay.id }
    var exercise_id: UUID { exercise.id }

    init(order: Int, splitDay: SplitDay, exercise: Exercise) {
        self.order = order
        self.splitDay = splitDay
        self.exercise = exercise
    }
}
