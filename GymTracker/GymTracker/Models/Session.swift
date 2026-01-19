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
    
    @Relationship(deleteRule: .nullify)
    var splitDay: SplitDay?
    var split_day_id: UUID? { splitDay?.id }
    
    @Relationship(deleteRule: .cascade, inverse: \SessionExercise.session)
    var sessionExercises: [SessionExercise] = []

    init (timestamp: Date, user_id: UUID, splitDay: SplitDay?, notes: String) {
        self.timestamp = timestamp
        self.user_id = user_id
        self.notes = notes
        self.splitDay = splitDay
        self.timestampDone = timestamp
    }
}
