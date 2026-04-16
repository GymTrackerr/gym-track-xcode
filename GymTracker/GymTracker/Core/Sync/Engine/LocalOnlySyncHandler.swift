//
//  LocalOnlySyncHandler.swift
//  GymTracker
//
//  Created by Codex on 2026-04-16.
//

import Foundation

/// Placeholder handler used while a feature has no remote sync implementation.
///
/// It intentionally performs no network operation so the app can remain
/// local-first without requiring fake remote repositories.
struct LocalOnlySyncHandler: SyncModelSyncHandler {
    let modelType: SyncModelType

    func process(item: SyncQueueItem) async throws {
        // No-op by design.
    }
}