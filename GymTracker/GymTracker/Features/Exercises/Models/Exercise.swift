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
    var isArchived: Bool = false
    var soft_deleted: Bool = false
    var syncMetaId: UUID? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var timestamp: Date

    // deletes the exerise split day
    @Relationship(deleteRule: .cascade)
    var splits: [ExerciseSplitDay]

    @Relationship(deleteRule: .cascade)
    var sessionEntries: [SessionEntry]

    var exerciseType: ExerciseType {
        ExerciseType.fromPersisted(rawValue: type)
    }

    var cardio: Bool {
        exerciseType == .cardio
    }

    init(name:String, type: ExerciseType=ExerciseType.weight, user_id: UUID, isUserCreated: Bool = true) {
        let timestamp = Date()

        self.name = name
        self.type = type.rawValue
        self.user_id = user_id
        self.timestamp = timestamp
        self.createdAt = timestamp
        self.updatedAt = timestamp
        self.isUserCreated = isUserCreated
        self.splits = []
        self.sessionEntries = []
    }
    
    init(from api: ExerciseDTO, userId: UUID) {
        let timestamp = Date()

        self.npId = api.id
        self.isUserCreated = false
        self.user_id = userId

        self.name = api.name
        self.type = ExerciseType.from(apiCategory: api.category).rawValue
        self.primary_muscles = api.primaryMuscles
        self.secondary_muscles = api.secondaryMuscles
        self.equipment = api.equipment
        self.category = api.category
        self.instructions = api.instructions
        self.images = api.images
        self.timestamp = timestamp
        self.createdAt = timestamp
        self.updatedAt = timestamp
        self.splits = []
        self.sessionEntries = []
    }

    // WARNING: Do not use for persisted entities. Always prefer init(from:userId:)
    convenience init(from api: ExerciseDTO) {
        self.init(from: api, userId: UUID())
    }
}


enum ExerciseType: Int, CaseIterable, Identifiable {
    case strength = 0
    case stretching = 1
    case strongman = 2
    case plyometrics = 3
    case weight = 4
    case cardio = 5
    
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
            return "Plyometrics"
        case .weight:
            return "Weight"
        case .cardio:
            return "Cardio"
//        default:
//            return "Unknown"
        }
    }
}

extension ExerciseType {
    static func from(apiCategory: String) -> ExerciseType {
        let normalized = apiCategory
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "cardio":
            return .cardio
        case "strength", "powerlifting", "olympic weightlifting":
            return .strength
        case "stretching":
            return .stretching
        case "strongman":
            return .strongman
        case "plyometrics":
            return .plyometrics
        default:
            return .weight
        }
    }

    static func from(apiCategory: String?) -> ExerciseType {
        guard let apiCategory else { return .weight }
        return from(apiCategory: apiCategory)
    }

    static func fromPersisted(rawValue: Int) -> ExerciseType {
        if let resolved = ExerciseType(rawValue: rawValue) {
            return resolved
        }

        // Backward compatibility for previously persisted types.
        if rawValue == 6 || rawValue == 7 {
            return .cardio
        }

        return .weight
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

extension Exercise {
    convenience init(from api: GymTrackerExerciseDTO, userId: UUID) {
        self.init(name: api.name, type: ExerciseType.from(apiCategory: api.type), user_id: userId, isUserCreated: api.isUserCreated)

        if api.source == "catalog" {
            self.npId = api.id
        } else if let remoteUUID = UUID(uuidString: api.id) {
            self.id = remoteUUID
        }

        self.aliases = api.aliases
        self.primary_muscles = api.primaryMuscles
        self.secondary_muscles = api.secondaryMuscles
        self.equipment = api.equipment
        self.category = api.category
        self.instructions = api.instructions
        self.images = api.images
        self.isArchived = api.isArchived
        self.soft_deleted = api.isArchived
    }
}

extension Exercise: SyncTrackedRoot {
    static var syncModelType: SyncModelType { .exercise }

    var syncSeedDate: Date { timestamp }

    var legacyDeleteBridgeValue: Bool? { isArchived }

    func applyLegacyDeleteBridge(_ value: Bool) {
        isArchived = value
    }
}
