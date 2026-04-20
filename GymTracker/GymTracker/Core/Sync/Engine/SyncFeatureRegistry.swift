//
//  SyncFeatureRegistry.swift
//  GymTracker
//
//  Created by Codex on 2026-04-16.
//

import Foundation

struct SyncFeatureRegistry {
    static func makeHandlers(
        remoteExerciseRepository: RemoteExerciseRepository? = nil
    ) -> [any SyncModelSyncHandler] {
        let exerciseHandler: any SyncModelSyncHandler = {
            guard let remoteExerciseRepository else {
                return LocalOnlySyncHandler(modelType: .exercise)
            }

            return ExerciseSyncHandler(remoteExerciseRepository: remoteExerciseRepository)
        }()

        return [
            exerciseHandler,
            LocalOnlySyncHandler(modelType: .routine),
            LocalOnlySyncHandler(modelType: .session),
            LocalOnlySyncHandler(modelType: .foodItem),
            LocalOnlySyncHandler(modelType: .mealRecipe),
            LocalOnlySyncHandler(modelType: .nutritionLogEntry),
            LocalOnlySyncHandler(modelType: .nutritionTarget),
            LocalOnlySyncHandler(modelType: .healthDailySummary),
            LocalOnlySyncHandler(modelType: .userProfile),
            LocalOnlySyncHandler(modelType: .program),
            LocalOnlySyncHandler(modelType: .progressionProfile),
            LocalOnlySyncHandler(modelType: .progressionExercise)
        ]
    }
}
