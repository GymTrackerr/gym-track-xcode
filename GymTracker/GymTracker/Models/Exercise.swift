//
//  Exercise.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import Foundation
import SwiftData

@Model
final class Exercise {
    var id: UUID = UUID()
    var npId: String? = nil
    var name: String
    var aliases: [String]? = []
    var type: Int = ExerciseType.weight.id
    var muscle_groups: [String]? = []
    var timestamp: Date

    @Relationship(deleteRule: .cascade, inverse: \ExerciseSplitDay.exercise)
    var splits: [ExerciseSplitDay] = []

    @Relationship(deleteRule: .cascade, inverse: \SessionExercise.exercise)
    var sessionExercises: [SessionExercise] = []

    var exerciseType: ExerciseType {
        ExerciseType(rawValue: type) ?? ExerciseType.weight
    }

    init(name:String, type: ExerciseType=ExerciseType.weight) {
        self.name = name
        self.type = type.rawValue
        self.timestamp = Date()
    }
}


enum ExerciseType: Int, CaseIterable, Identifiable {
    case weight, run, bike, swim
    
    var id: Int { return self.rawValue }

    var name: String {
        switch self {
        case .weight:
            return "Weight"
        case .run:
            return "Run"
        case .bike:
            return "Bike"
        case .swim:
            return "Swim"
//        default:
//            return "Unknown"
        }
    }
}
