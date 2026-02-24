//
//  Routine.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import Foundation
import SwiftData

@Model
final class Routine {
    var id: UUID = UUID()
    var user_id: UUID
    var order: Int
    var name: String
    var timestamp: Date
    var aliases: [String] = []
    
    @Relationship(deleteRule: .cascade)
    var exerciseSplits: [ExerciseSplitDay]
    
    @Relationship(deleteRule: .nullify)
    var sessions: [Session]
    
    init(order: Int, name: String, user_id: UUID) {
        self.order = order
        self.name = name
        self.user_id = user_id
        self.timestamp = Date()
        self.exerciseSplits = []
        self.sessions = []
    }
}
