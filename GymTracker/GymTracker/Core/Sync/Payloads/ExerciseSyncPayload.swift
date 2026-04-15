//
//  ExerciseSyncPayload.swift
//  GymTracker
//
//  Created by Codex on 2026-04-15.
//

import Foundation

struct ExerciseSyncPayload: Codable {
    let id: String
    let npId: String?
    let name: String
    let aliases: [String]
    let type: Int
    let userId: String
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let equipment: String?
    let category: String?
    let instructions: [String]
    let images: [String]
    let isUserCreated: Bool
    let isArchived: Bool
    let softDeleted: Bool
    let createdAt: Date
    let updatedAt: Date

    init(exercise: Exercise) {
        self.id = exercise.id.uuidString.lowercased()
        self.npId = exercise.npId
        self.name = exercise.name
        self.aliases = exercise.aliases ?? []
        self.type = exercise.type
        self.userId = exercise.user_id.uuidString.lowercased()
        self.primaryMuscles = exercise.primary_muscles ?? []
        self.secondaryMuscles = exercise.secondary_muscles ?? []
        self.equipment = exercise.equipment
        self.category = exercise.category
        self.instructions = exercise.instructions ?? []
        self.images = exercise.images ?? []
        self.isUserCreated = exercise.isUserCreated
        self.isArchived = exercise.isArchived
        self.softDeleted = exercise.soft_deleted
        self.createdAt = exercise.createdAt
        self.updatedAt = exercise.updatedAt
    }
}
