//
//  ExerciseAPI.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-11-11.
//

import Foundation

final class ExerciseApi {
    private let apiHelper: API_Helper

    init(apiHelper: API_Helper = API_Helper()) {
        self.apiHelper = apiHelper
    }

    // get post replies
    func getExercises() async throws -> [ExerciseDTO] {
        print("replies of post")
        do {
            let response: ListResponse<ExerciseDTO> = try await apiHelper.asyncRequestListData(route: APIRoute.exercises)
            return response.items
        } catch {
            print(error)
            throw error
        }
    }
    
    func getExercise(exerciseID: String) async throws -> ExerciseDTO {
        print("replies of post")
        do {
            let data: ExerciseDTO = try await apiHelper.asyncRequestData(route: APIRoute.exercise(id: exerciseID))
            return data
        } catch {
            print(error)
            throw error
        }
    }
}
