//
//  SyncWorker.swift
//  GymTracker
//
//  Created by Codex on 2026-04-15.
//

import Foundation

enum SyncWorkerResult: Equatable {
    case noWork
    case notEligible
    case processedItem
    case unsupportedItemSkipped
}

final class SyncWorker {
    private let queueStore: SyncQueueStore
    private let metadataStore: SyncMetadataStore
    private let eligibilityService: SyncEligibilityService
    private let handlersByModelType: [SyncModelType: any SyncModelSyncHandler]

    init(
        queueStore: SyncQueueStore,
        metadataStore: SyncMetadataStore,
        eligibilityService: SyncEligibilityService,
        handlers: [any SyncModelSyncHandler]
    ) {
        self.queueStore = queueStore
        self.metadataStore = metadataStore
        self.eligibilityService = eligibilityService
        self.handlersByModelType = Dictionary(uniqueKeysWithValues: handlers.map { ($0.modelType, $0) })
    }

    func processNextEligibleItem(referenceDate: Date = Date()) async throws -> SyncWorkerResult {
        guard eligibilityService.isProcessingEligible else {
            return .notEligible
        }

        let supportedModelTypes = Array(handlersByModelType.keys)

        guard let item = try queueStore.nextReadyItem(
            referenceDate: referenceDate,
            supportedModelTypes: supportedModelTypes
        ) else {
            return .noWork
        }

        do {
            guard let modelType = SyncModelType(rawValue: item.modelTypeRaw) else {
                try queueStore.markDeadLetter(
                    item,
                    errorCode: "UNSUPPORTED_MODEL_TYPE",
                    errorMessage: "Queue item model type is unknown.",
                    at: referenceDate
                )
                return .unsupportedItemSkipped
            }

            guard let handler = handlersByModelType[modelType] else {
                try queueStore.markDeadLetter(
                    item,
                    errorCode: "UNSUPPORTED_MODEL_TYPE",
                    errorMessage: "Remote sync is not enabled for this model type yet.",
                    at: referenceDate
                )
                return .unsupportedItemSkipped
            }

            try queueStore.markInFlight(item, at: referenceDate)
            try metadataStore.markSyncing(
                modelType: modelType,
                linkedItemId: item.linkedItemId,
                at: referenceDate
            )

            try await handler.process(item: item)

            try metadataStore.markSynced(
                modelType: modelType,
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
}
