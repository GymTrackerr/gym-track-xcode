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
    var user_id: UUID
    
    var primary_muscles: [String]? = []
    var secondary_muscles: [String]? = []
    
    var equipment: String? = nil         // e.g. "barbell", "body only"
    var category: String? = nil          // e.g. "strength", "stretching"
    var instructions: [String]? = []     // Optional — only from API
    var images: [String]? = []          // Relative image URLs
    var cachedMedia: Bool? = false
    var isUserCreated: Bool = true       // Key flag
    var timestamp: Date

    // deletes the exerise split day
    @Relationship(deleteRule: .cascade)
    var splits: [ExerciseSplitDay]

    @Relationship(deleteRule: .cascade)
    var sessionEntries: [SessionEntry]

    var exerciseType: ExerciseType {
        ExerciseType(rawValue: type) ?? ExerciseType.weight
    }

    init(name:String, type: ExerciseType=ExerciseType.weight, user_id: UUID, isUserCreated: Bool = true) {
        self.name = name
        self.type = type.rawValue
        self.user_id = user_id
        self.timestamp = Date()
        self.isUserCreated = isUserCreated
        self.splits = []
        self.sessionEntries = []
    }
    
    init(from api: ExerciseDTO) {
        self.npId = api.id
        self.isUserCreated = false
        self.user_id = UUID() // API exercises get a new UUID, will be associated with user creating them

        self.name = api.name
        self.primary_muscles = api.primaryMuscles
        self.secondary_muscles = api.secondaryMuscles
        self.equipment = api.equipment
        self.category = api.category
        self.instructions = api.instructions
        self.images = api.images
        self.timestamp = Date()
        self.splits = []
        self.sessionEntries = []
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
