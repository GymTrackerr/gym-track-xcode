//
//  SyncMetadataStore.swift
//  GymTracker
//
//  Created by Codex on 2026-04-15.
//

import Foundation
import SwiftData

final class SyncMetadataStore {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func markSyncing(modelType: SyncModelType, linkedItemId: String, at timestamp: Date = Date()) throws {
        guard let metadata = try fetchMetadata(modelType: modelType, linkedItemId: linkedItemId) else { return }
        metadata.syncState = .syncing
        metadata.updatedAt = timestamp
        metadata.lastErrorCode = nil
        metadata.lastErrorMessage = nil
        try modelContext.save()
    }

    func markSynced(modelType: SyncModelType, linkedItemId: String, at timestamp: Date = Date()) throws {
        guard let metadata = try fetchMetadata(modelType: modelType, linkedItemId: linkedItemId) else { return }
        metadata.syncState = .synced
        metadata.lastSyncedAt = timestamp
        metadata.updatedAt = timestamp
        metadata.lastErrorCode = nil
        metadata.lastErrorMessage = nil
        try modelContext.save()
    }

    func markConflict(
        modelType: SyncModelType,
        linkedItemId: String,
        errorCode: String?,
        message: String?,
        at timestamp: Date = Date()
    ) throws {
        guard let metadata = try fetchMetadata(modelType: modelType, linkedItemId: linkedItemId) else { return }
        metadata.syncState = .conflict
        metadata.lastErrorCode = errorCode
        metadata.lastErrorMessage = message
        metadata.updatedAt = timestamp
        try modelContext.save()
    }

    func markFailed(
        modelType: SyncModelType,
        linkedItemId: String,
        errorCode: String?,
        message: String?,
        at timestamp: Date = Date()
    ) throws {
        guard let metadata = try fetchMetadata(modelType: modelType, linkedItemId: linkedItemId) else { return }
        metadata.syncState = .failed
        metadata.lastErrorCode = errorCode
        metadata.lastErrorMessage = message
        metadata.updatedAt = timestamp
        try modelContext.save()
    }

    private func fetchMetadata(
        modelType: SyncModelType,
        linkedItemId: String
    ) throws -> SyncMetadataItem? {
        let modelTypeRaw = modelType.rawValue
        let descriptor = FetchDescriptor<SyncMetadataItem>(
            predicate: #Predicate<SyncMetadataItem> { metadata in
                metadata.modelTypeRaw == modelTypeRaw && metadata.linkedItemId == linkedItemId
            }
        )
        return try modelContext.fetch(descriptor).first
    }
}
