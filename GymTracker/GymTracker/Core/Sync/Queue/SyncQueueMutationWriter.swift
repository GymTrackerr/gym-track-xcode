//
//  SyncQueueMutationWriter.swift
//  GymTracker
//
//  Created by Codex on 2026-04-15.
//

import Foundation

enum SyncQueueMutationWriter {
    private static let encoder = JSONEncoder()

    static func enqueueIfNeeded<Root: SyncTrackedRoot>(
        root: Root,
        operation: SyncQueueOperation,
        queueStore: SyncQueueStore,
        eligibilityService: SyncEligibilityService,
        payloadData: Data? = nil,
        dependencyKey: String? = nil
    ) {
        guard eligibilityService.isQueueingAllowed else { return }

        do {
            let data = try payloadData ?? encoder.encode(SyncRootSnapshotPayload(root))
            try queueStore.enqueueMutation(
                modelType: Root.syncModelType,
                linkedItemId: root.syncLinkedItemId,
                operation: operation,
                payloadSnapshotData: data,
                dependencyKey: dependencyKey ?? defaultDependencyKey(for: root)
            )
        } catch {
            print("Failed to enqueue sync mutation for \(Root.syncModelType) root \(root.syncLinkedItemId): \(error)")
        }
    }

    private static func defaultDependencyKey<Root: SyncTrackedRoot>(for root: Root) -> String {
        "\(Root.syncModelType.rawValue):\(root.syncLinkedItemId)"
    }
}
