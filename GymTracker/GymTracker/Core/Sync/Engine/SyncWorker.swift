//
//  SyncWorker.swift
//  GymTracker
//
//  Created by Codex on 2026-04-15.
//

import Foundation

enum SyncWorkerResult: Equatable {
    case noWork
    case remoteExecutionDisabled
    case processedItem
    case unsupportedItemSkipped
}

final class SyncWorker {
    private let queueStore: SyncQueueStore
    private let metadataStore: SyncMetadataStore
    private let remoteExerciseRepository: RemoteExerciseRepository
    private let remoteExecutionEnabled: Bool

    init(
        queueStore: SyncQueueStore,
        metadataStore: SyncMetadataStore,
        remoteExerciseRepository: RemoteExerciseRepository,
        remoteExecutionEnabled: Bool = false
    ) {
        self.queueStore = queueStore
        self.metadataStore = metadataStore
        self.remoteExerciseRepository = remoteExerciseRepository
        self.remoteExecutionEnabled = remoteExecutionEnabled
    }

    func processNextEligibleItem(referenceDate: Date = Date()) throws -> SyncWorkerResult {
        guard remoteExecutionEnabled else {
            return .remoteExecutionDisabled
        }

        guard let item = try queueStore.nextReadyItem(
            referenceDate: referenceDate,
            supportedModelTypes: [.exercise]
        ) else {
            return .noWork
        }

        do {
            try queueStore.markInFlight(item, at: referenceDate)
            try metadataStore.markSyncing(
                modelType: SyncModelType(rawValue: item.modelTypeRaw) ?? .exercise,
                linkedItemId: item.linkedItemId,
                at: referenceDate
            )

            switch item.modelType {
            case .exercise:
                try processExerciseItem(item)
            default:
                try queueStore.markDeadLetter(
                    item,
                    errorCode: "UNSUPPORTED_MODEL_TYPE",
                    errorMessage: "Remote sync is not enabled for this model type yet.",
                    at: referenceDate
                )
                return .unsupportedItemSkipped
            }

            try metadataStore.markSynced(
                modelType: SyncModelType(rawValue: item.modelTypeRaw) ?? .exercise,
                linkedItemId: item.linkedItemId,
                at: Date()
            )
            try queueStore.remove(item)
            return .processedItem
        } catch let error as APIHelperError {
            try handleAPIError(error, for: item)
            return .processedItem
        } catch {
            try queueStore.markRetryScheduled(
                item,
                errorCode: "SYNC_WORKER_ERROR",
                errorMessage: error.localizedDescription,
                at: Date()
            )
            try metadataStore.markFailed(
                modelType: SyncModelType(rawValue: item.modelTypeRaw) ?? .exercise,
                linkedItemId: item.linkedItemId,
                errorCode: "SYNC_WORKER_ERROR",
                message: error.localizedDescription,
                at: Date()
            )
            return .processedItem
        }
    }

    private func processExerciseItem(_ item: SyncQueueItem) throws {
        guard let payloadData = item.payloadSnapshotData else {
            throw APIHelperError.httpError(
                statusCode: 0,
                code: "MISSING_PAYLOAD",
                message: "Queue item payload is missing.",
                details: nil
            )
        }

        let payload = try JSONDecoder().decode(ExerciseSyncPayload.self, from: payloadData)
        let exercise = makeExercise(from: payload)
        let semaphore = DispatchSemaphore(value: 0)
        var taskError: Error?

        Task {
            do {
                switch item.operation {
                case .create, .update:
                    _ = try await remoteExerciseRepository.upsertUserExercise(exercise)
                case .softDelete:
                    try await remoteExerciseRepository.deleteUserExercise(id: payload.id)
                case .restore:
                    _ = try await remoteExerciseRepository.restoreUserExercise(id: payload.id)
                case .hardDelete, .none:
                    throw APIHelperError.httpError(
                        statusCode: 0,
                        code: "UNSUPPORTED_OPERATION",
                        message: "Exercise sync does not support this operation.",
                        details: nil
                    )
                }
            } catch {
                taskError = error
            }
            semaphore.signal()
        }

        semaphore.wait()
        if let taskError {
            throw taskError
        }
    }

    private func handleAPIError(_ error: APIHelperError, for item: SyncQueueItem) throws {
        let modelType = SyncModelType(rawValue: item.modelTypeRaw) ?? .exercise

        switch error {
        case .httpError(let statusCode, let code, let message, let details):
            if statusCode == 409 {
                try metadataStore.markConflict(
                    modelType: modelType,
                    linkedItemId: item.linkedItemId,
                    errorCode: code,
                    message: message ?? details,
                    at: Date()
                )
                try queueStore.remove(item)
                return
            }

            if statusCode == 400 || statusCode == 403 {
                try metadataStore.markFailed(
                    modelType: modelType,
                    linkedItemId: item.linkedItemId,
                    errorCode: code,
                    message: message ?? details,
                    at: Date()
                )
                try queueStore.markDeadLetter(
                    item,
                    errorCode: code,
                    errorMessage: message ?? details,
                    at: Date()
                )
                return
            }

            try metadataStore.markFailed(
                modelType: modelType,
                linkedItemId: item.linkedItemId,
                errorCode: code,
                message: message ?? details,
                at: Date()
            )
            try queueStore.markRetryScheduled(
                item,
                errorCode: code,
                errorMessage: message ?? details,
                at: Date()
            )
        case .missingAccessToken:
            try metadataStore.markFailed(
                modelType: modelType,
                linkedItemId: item.linkedItemId,
                errorCode: "MISSING_ACCESS_TOKEN",
                message: "Missing access token.",
                at: Date()
            )
            try queueStore.markRetryScheduled(
                item,
                errorCode: "MISSING_ACCESS_TOKEN",
                errorMessage: "Missing access token.",
                at: Date()
            )
        case .invalidResponse:
            try metadataStore.markFailed(
                modelType: modelType,
                linkedItemId: item.linkedItemId,
                errorCode: "INVALID_RESPONSE",
                message: "Invalid backend response.",
                at: Date()
            )
            try queueStore.markRetryScheduled(
                item,
                errorCode: "INVALID_RESPONSE",
                errorMessage: "Invalid backend response.",
                at: Date()
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
