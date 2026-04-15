//
//  SyncQueueItem.swift
//  GymTracker
//
//  Created by Codex on 2026-04-15.
//

import Foundation
import SwiftData

@Model
final class SyncQueueItem {
    @Attribute(.unique) var id: UUID
    var modelTypeRaw: Int
    var linkedItemId: String
    var operationRaw: Int
    var payloadSnapshotData: Data?
    var dependencyKey: String?
    var priority: Int
    var statusRaw: Int
    var attemptCount: Int
    var nextAttemptAt: Date
    var lastAttemptAt: Date?
    var lastErrorCode: String?
    var lastErrorMessage: String?
    var requiresAuth: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        modelType: SyncModelType,
        linkedItemId: String,
        operation: SyncQueueOperation,
        payloadSnapshotData: Data? = nil,
        dependencyKey: String? = nil,
        priority: Int = 100,
        status: SyncQueueStatus = .queued,
        attemptCount: Int = 0,
        nextAttemptAt: Date? = nil,
        lastAttemptAt: Date? = nil,
        lastErrorCode: String? = nil,
        lastErrorMessage: String? = nil,
        requiresAuth: Bool = true,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        let timestamp = Date()
        let resolvedCreatedAt = createdAt ?? timestamp
        let resolvedUpdatedAt = max(updatedAt ?? resolvedCreatedAt, resolvedCreatedAt)

        self.id = id
        self.modelTypeRaw = modelType.rawValue
        self.linkedItemId = linkedItemId
        self.operationRaw = operation.rawValue
        self.payloadSnapshotData = payloadSnapshotData
        self.dependencyKey = dependencyKey
        self.priority = priority
        self.statusRaw = status.rawValue
        self.attemptCount = attemptCount
        self.nextAttemptAt = nextAttemptAt ?? resolvedUpdatedAt
        self.lastAttemptAt = lastAttemptAt
        self.lastErrorCode = lastErrorCode
        self.lastErrorMessage = lastErrorMessage
        self.requiresAuth = requiresAuth
        self.createdAt = resolvedCreatedAt
        self.updatedAt = resolvedUpdatedAt
    }
    
    var modelType: SyncModelType? {
        get { SyncModelType(rawValue: modelTypeRaw) }
        set { modelTypeRaw = newValue?.rawValue ?? modelTypeRaw }
    }

    var operation: SyncQueueOperation? {
        get { SyncQueueOperation(rawValue: operationRaw) }
        set { operationRaw = newValue?.rawValue ?? operationRaw }
    }

    var status: SyncQueueStatus {
        get { SyncQueueStatus(rawValue: statusRaw) ?? .queued }
        set { statusRaw = newValue.rawValue }
    }
}
