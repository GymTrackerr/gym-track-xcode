//
//  SessionExercise.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-04.
//

import Foundation
import SwiftData

// join table
@Model
final class SessionExercise {
//    @Attribute(.unique)
    var id: UUID = UUID()
    var order: Int
    
    var isCompleted: Bool = false
    
    var exercise: Exercise
    var session: Session
    
//    @Relationship(deleteRule: .cascade, inverse: \Sets.sessionExercise)
//    var sets: [Session]
    
    var exercise_id: UUID { exercise.id }
    var session_id: UUID { session.id }
    
    // construct without split day
    init(order: Int, session: Session, exercise: Exercise) {
        self.order = order;
        self.session = session;
        self.exercise = exercise
    }
    
    // construct via exerciseSplitDay
    convenience init(session: Session, exerciseSplitDay: ExerciseSplitDay) {
        self.init(order: exerciseSplitDay.order, session: session, exercise: exerciseSplitDay.exercise)
    }
}
