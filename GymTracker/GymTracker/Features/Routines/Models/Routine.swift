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
    var isArchived: Bool = false
    var isBuiltIn: Bool = false
    var builtInKey: String? = nil
    var aliases: [String] = []
    
    @Relationship(deleteRule: .cascade)
    var exerciseSplits: [ExerciseSplitDay]
    
    @Relationship(deleteRule: .nullify)
    var sessions: [Session] = []

    @Relationship(deleteRule: .nullify, inverse: \ProgramDay.routine)
    var programDays: [ProgramDay] = []
    
    init(
        order: Int,
        name: String,
        user_id: UUID,
        isBuiltIn: Bool = false,
        builtInKey: String? = nil
    ) {
        self.order = order
        self.name = name
        self.user_id = user_id
        self.isBuiltIn = isBuiltIn
        self.builtInKey = builtInKey
        self.timestamp = Date()
        self.exerciseSplits = []
        self.sessions = []
        self.programDays = []
    }
}
