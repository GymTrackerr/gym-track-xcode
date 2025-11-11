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
    var equipment: String? = nil         // e.g. "barbell", "body only"
    var category: String? = nil          // e.g. "strength", "stretching"
    var instructions: [String]? = []     // Optional — only from API
    var imagePaths: [String]? = []       // Relative image URLs
    var isUserCreated: Bool = true       // Key flag
    var timestamp: Date

    // deletes the exerise split day
    @Relationship(deleteRule: .cascade, inverse: \ExerciseSplitDay.exercise)
    var splits: [ExerciseSplitDay] = []

    @Relationship(deleteRule: .cascade, inverse: \SessionExercise.exercise)
    var sessionExercises: [SessionExercise] = []

    var exerciseType: ExerciseType {
        ExerciseType(rawValue: type) ?? ExerciseType.weight
    }

    init(name:String, type: ExerciseType=ExerciseType.weight, isUserCreated: Bool = true) {
        self.name = name
        self.type = type.rawValue
        self.timestamp = Date()
        self.isUserCreated = isUserCreated
    }
    
    // ✅ New init for API decoding
    init(from api: ExerciseDTO) {
        self.name = api.name
        self.npId = api.id
        self.isUserCreated = false
        self.muscle_groups = api.primaryMuscles
        self.equipment = api.equipment
        self.category = api.category
        self.instructions = api.instructions
        self.imagePaths = api.images
        self.timestamp = Date()
    }
}


enum ExerciseType: Int, CaseIterable, Identifiable {
    case strength, stretching, strongman, plyometrics, weight, run, bike, swim
    
    var id: Int { return self.rawValue }

    var name: String {
        switch self {
        case .strength:
            return "Strength"
        case .stretching:
            return "Stretching"
        case .strongman:
            return "Strongman"
        case .plyometrics:
            return "plyometrics"
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


struct ExerciseDTO: Identifiable, Codable {
    let id: String
    let name: String
    let force: String?
    let level: String?
    let mechanic: String?
    let equipment: String?
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let instructions: [String]
    let category: String
    let images: [String]
}
