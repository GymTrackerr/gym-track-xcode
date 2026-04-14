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
