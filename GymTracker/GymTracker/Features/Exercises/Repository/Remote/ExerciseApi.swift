//
//  ExerciseAPI.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-11-11.
//

import Foundation

// Legacy direct ExerciseDB client used for local-only catalog refresh paths during migration.
final class ExerciseApi {
    private let apiHelper: API_Helper

    init(apiHelper: API_Helper = API_Helper()) {
        self.apiHelper = apiHelper
    }

    // get post replies
    func getExercises() async throws -> [ExerciseDTO] {
        print("replies of post")
        do {
            let APIUrl = apiHelper.baseAPIurl + "/exercisedb"
            return try await apiHelper.asyncRequestData(urlString: APIUrl)
        } catch {
            print(error)
            throw error
        }
    }
    
    func getExercise(exerciseID: String) async throws -> ExerciseDTO {
        print("replies of post")
        do {
            let APIUrl = apiHelper.baseAPIurl + "/exercisedb/" + exerciseID
            return try await apiHelper.asyncRequestData(urlString: APIUrl)
        } catch {
            print(error)
            throw error
        }
    }
}

struct GymTrackerExerciseDTO: Identifiable, Codable {
    let id: String
    let source: String
    let name: String
    let type: String
    let aliases: [String]
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let equipment: String?
    let category: String?
    let instructions: [String]
    let images: [String]
    let isUserCreated: Bool
    let isArchived: Bool
    let isEditable: Bool
    let isDeletable: Bool
    let createdAt: String?
    let updatedAt: String?
    let deletedAt: String?
}

// GymTracker backend client for signed-in remote exercise reads/writes.
final class GymTrackerExerciseApi {
    private let apiHelper: API_Helper

    init(apiHelper: API_Helper = API_Helper()) {
        self.apiHelper = apiHelper
    }

    func getExercises() async throws -> [GymTrackerExerciseDTO] {
        let response: ListResponse<GymTrackerExerciseDTO> =
            try await apiHelper.asyncAuthorizedRequestListData(route: APIRoute.exercises)
        return response.items
    }

    func getExercise(exerciseID: String) async throws -> GymTrackerExerciseDTO {
        try await apiHelper.asyncAuthorizedRequestData(route: APIRoute.exercise(id: exerciseID))
    }
}
