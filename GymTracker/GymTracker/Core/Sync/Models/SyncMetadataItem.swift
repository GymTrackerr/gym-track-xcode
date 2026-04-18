//
//  SyncMetadataItem.swift
//  GymTracker
//
//  Created by Codex on 2026-04-15.
//

import Foundation
import SwiftData

@Model
final class SyncMetadataItem {
    @Attribute(.unique) var id: UUID
    var linkedItemId: String
    var modelTypeRaw: Int
    var localVersion: Int
    var remoteVersion: Int?
    var lastSyncedAt: Date?
    var syncStateRaw: Int
    var lastErrorCode: String?
    var lastErrorMessage: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        linkedItemId: String,
        modelType: SyncModelType,
        localVersion: Int = 0,
        remoteVersion: Int? = nil,
        lastSyncedAt: Date? = nil,
        syncState: SyncMetadataState = .pending,
        lastErrorCode: String? = nil,
        lastErrorMessage: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        let timestamp = Date()
        let resolvedCreatedAt = createdAt ?? timestamp
        let resolvedUpdatedAt = max(updatedAt ?? resolvedCreatedAt, resolvedCreatedAt)

        self.id = id
        self.linkedItemId = linkedItemId
        self.modelTypeRaw = modelType.rawValue
        self.localVersion = localVersion
        self.remoteVersion = remoteVersion
        self.lastSyncedAt = lastSyncedAt
        self.syncStateRaw = syncState.rawValue
        self.lastErrorCode = lastErrorCode
        self.lastErrorMessage = lastErrorMessage
        self.createdAt = resolvedCreatedAt
        self.updatedAt = resolvedUpdatedAt
    }

    var modelType: SyncModelType? {
        get { SyncModelType(rawValue: modelTypeRaw) }
        set { modelTypeRaw = newValue?.rawValue ?? modelTypeRaw }
    }

    var syncState: SyncMetadataState {
        get { SyncMetadataState(rawValue: syncStateRaw) ?? .pending }
        set { syncStateRaw = newValue.rawValue }
    }
}
