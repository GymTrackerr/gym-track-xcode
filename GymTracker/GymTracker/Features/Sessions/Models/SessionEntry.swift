//
//  SessionEntry.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-04.
//

import Foundation
import SwiftData

@Model
final class SessionEntry {
//    @Attribute(.unique)
    var id: UUID = UUID()
    var order: Int
    
    var isCompleted: Bool = false
    
    var exercise: Exercise
    
    var session: Session

    var appliedSetsTarget: Int?
    var appliedRepsTarget: Int?
    var appliedRepsLow: Int?
    var appliedRepsHigh: Int?
    var appliedProgression: ProgressionProfile?
    var appliedProgressionNameSnapshot: String?
    var suggestedWeight: Double?
    
    @Relationship(deleteRule: .cascade)
    var sets: [SessionSet]
    
    var exercise_id: UUID { exercise.id }
    var session_id: UUID { session.id }
    
    // construct without split day
    init(order: Int, session: Session, exercise: Exercise) {
        self.order = order
        self.session = session
        self.exercise = exercise
        self.appliedSetsTarget = nil
        self.appliedRepsTarget = nil
        self.appliedRepsLow = nil
        self.appliedRepsHigh = nil
        self.appliedProgression = nil
        self.appliedProgressionNameSnapshot = nil
        self.suggestedWeight = nil
        self.sets = []
    }
    
    // construct via exerciseSplitDay
    convenience init(session: Session, exerciseSplitDay: ExerciseSplitDay) {
        self.init(order: exerciseSplitDay.order, session: session, exercise: exerciseSplitDay.exercise)
    }
}
