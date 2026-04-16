//
//  ExerciseSyncHandler.swift
//  GymTracker
//
//  Created by Codex on 2026-04-16.
//

import Foundation

final class ExerciseSyncHandler: SyncModelSyncHandler {
    let modelType: SyncModelType = .exercise

    private let remoteExerciseRepository: RemoteExerciseRepository

    init(remoteExerciseRepository: RemoteExerciseRepository) {
        self.remoteExerciseRepository = remoteExerciseRepository
    }

    func process(item: SyncQueueItem) async throws {
        guard let payloadData = item.payloadSnapshotData else {
            throw APIHelperError.httpError(
                statusCode: 400,
                code: "MISSING_PAYLOAD",
                message: "Queue item payload is missing.",
                details: nil
            )
        }

        let payload: ExerciseSyncPayload
        do {
            payload = try JSONDecoder().decode(ExerciseSyncPayload.self, from: payloadData)
        } catch {
            throw APIHelperError.httpError(
                statusCode: 400,
                code: "INVALID_PAYLOAD",
                message: "Queue item payload could not be decoded.",
                details: error.localizedDescription
            )
        }
        let exercise = makeExercise(from: payload)

        switch item.operation {
        case .create, .update:
            _ = try await remoteExerciseRepository.upsertUserExercise(exercise)
        case .softDelete:
            try await remoteExerciseRepository.deleteUserExercise(id: payload.id)
        case .restore:
            _ = try await remoteExerciseRepository.restoreUserExercise(id: payload.id)
        case .hardDelete, .none:
            throw APIHelperError.httpError(
                statusCode: 400,
                code: "UNSUPPORTED_OPERATION",
                message: "Exercise sync does not support this operation.",
                details: nil
            )
        }
    }

    private func makeExercise(from payload: ExerciseSyncPayload) -> Exercise {
        let userId = UUID(uuidString: payload.userId) ?? UUID()
        let exercise = Exercise(
            name: payload.name,
            type: ExerciseType.fromPersisted(rawValue: payload.type),
            user_id: userId,
            isUserCreated: payload.isUserCreated
        )
        if let id = UUID(uuidString: payload.id) {
            exercise.id = id
        }
        exercise.npId = payload.npId
        exercise.aliases = payload.aliases
        exercise.primary_muscles = payload.primaryMuscles
        exercise.secondary_muscles = payload.secondaryMuscles
        exercise.equipment = payload.equipment
        exercise.category = payload.category
        exercise.instructions = payload.instructions
        exercise.images = payload.images
        exercise.isArchived = payload.isArchived
        exercise.soft_deleted = payload.softDeleted
        exercise.createdAt = payload.createdAt
        exercise.updatedAt = payload.updatedAt
        exercise.timestamp = payload.createdAt
        return exercise
    }
}
