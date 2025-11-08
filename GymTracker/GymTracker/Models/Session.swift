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
    var timestamp: Date
    var timestampDone: Date = Date() // temporary just saving as 
    var notes: String = ""
    
//    @Relationship(deleteRule: .nullify)
    var splitDay: SplitDay?
    var split_day_id: UUID? { splitDay?.id }
    
    @Relationship(deleteRule: .cascade, inverse: \SessionExercise.session)
    var sessionExercises: [SessionExercise] = []

    init (timestamp: Date, splitDay: SplitDay?, notes: String) {
        self.timestamp = timestamp
        self.notes = notes
        self.splitDay = splitDay
        self.timestampDone = timestamp
    }
}
