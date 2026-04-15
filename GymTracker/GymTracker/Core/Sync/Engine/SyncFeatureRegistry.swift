//
//  SyncFeatureRegistry.swift
//  GymTracker
//
//  Created by Codex on 2026-04-16.
//

import Foundation

struct SyncFeatureRegistry {
    static func makeHandlers(
        remoteExerciseRepository: RemoteExerciseRepository
    ) -> [any SyncModelSyncHandler] {
        [
            ExerciseSyncHandler(remoteExerciseRepository: remoteExerciseRepository)
        ]
    }
}
