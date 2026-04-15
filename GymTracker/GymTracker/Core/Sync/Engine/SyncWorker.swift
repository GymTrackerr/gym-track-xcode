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
}

final class SyncWorker {
    private let queueStore: SyncQueueStore
    private let remoteExecutionEnabled: Bool

    init(
        queueStore: SyncQueueStore,
        remoteExecutionEnabled: Bool = false
    ) {
        self.queueStore = queueStore
        self.remoteExecutionEnabled = remoteExecutionEnabled
    }

    func processNextEligibleItem(referenceDate: Date = Date()) throws -> SyncWorkerResult {
        guard remoteExecutionEnabled else {
            return .remoteExecutionDisabled
        }

        guard let _ = try queueStore.nextReadyItem(referenceDate: referenceDate) else {
            return .noWork
        }

        return .remoteExecutionDisabled
    }
}
