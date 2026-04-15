//
//  BaseSyncRepository.swift
//  GymTracker
//
//  Created by Codex on 2026-04-16.
//

import Foundation

class BaseSyncRepository {
    let queueStore: SyncQueueStore
    let eligibilityService: SyncEligibilityService

    init(
        queueStore: SyncQueueStore,
        eligibilityService: SyncEligibilityService
    ) {
        self.queueStore = queueStore
        self.eligibilityService = eligibilityService
    }

    func enqueueRootMutationIfNeeded<Root: SyncTrackedRoot>(
        root: Root,
        operation: SyncQueueOperation,
        payloadData: Data? = nil,
        dependencyKey: String? = nil
    ) {
        SyncQueueMutationWriter.enqueueIfNeeded(
            root: root,
            operation: operation,
            queueStore: queueStore,
            eligibilityService: eligibilityService,
            payloadData: payloadData,
            dependencyKey: dependencyKey
        )
    }

    func enqueueMutationIfNeeded(
        modelType: SyncModelType,
        linkedItemId: String,
        operation: SyncQueueOperation,
        payloadData: Data?,
        dependencyKey: String? = nil
    ) {
        guard eligibilityService.isQueueingAllowed else { return }

        do {
            try queueStore.enqueueMutation(
                modelType: modelType,
                linkedItemId: linkedItemId,
                operation: operation,
                payloadSnapshotData: payloadData,
                dependencyKey: dependencyKey
            )
        } catch {
            print("Failed to enqueue sync mutation for model \(modelType) item \(linkedItemId): \(error)")
        }
    }
}
