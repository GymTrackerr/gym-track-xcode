//
//  ExerciseAPI.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-11-11.
//

class ExerciseApi: API_Base {
    // get post replies
    func getExercises() async throws -> [ExerciseDTO] {
        print("replies of post")
        let APIUrl = baseAPIurl + "/exercisedb"
        
        do {
            let data:[ExerciseDTO] = try await apiHelper.asyncRequestData(urlString: APIUrl, httpMethod: "GET");
            return data;
        } catch {
            print(error)
            throw error
        }
    }
    
    func getExercise(exerciseID: String) async throws -> ExerciseDTO {
        print("replies of post")
        let APIUrl = baseAPIurl + "/exercisedb/"+exerciseID
        
        do {
            let data:ExerciseDTO = try await apiHelper.asyncRequestData(urlString: APIUrl, httpMethod: "GET");
            return data;
        } catch {
            print(error)
            throw error
        }
    }
}
