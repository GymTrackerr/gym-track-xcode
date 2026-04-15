//
//  SyncRootMetadataManager.swift
//  GymTracker
//
//  Created by Codex on 2026-04-15.
//

import Foundation
import SwiftData

protocol SyncTrackedRoot: AnyObject {
    var id: UUID { get set }
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
    var soft_deleted: Bool { get set }
    var syncMetaId: UUID? { get set }

    static var syncModelType: SyncModelType { get }
    var syncSeedDate: Date { get }
    var legacyDeleteBridgeValue: Bool? { get }
    func applyLegacyDeleteBridge(_ value: Bool)
}

extension SyncTrackedRoot {
    var legacyDeleteBridgeValue: Bool? { nil }
    func applyLegacyDeleteBridge(_ value: Bool) {}
}

enum SyncRootMetadataManager {
    @discardableResult
    static func prepareForRead<Root: SyncTrackedRoot>(_ roots: [Root], in context: ModelContext) throws -> Bool {
        var didChange = false
        for root in roots {
            if try prepareForRead(root, in: context) {
                didChange = true
            }
        }
        return didChange
    }

    @discardableResult
    static func prepareForRead<Root: SyncTrackedRoot>(_ root: Root, in context: ModelContext) throws -> Bool {
        var didChange = normalizeInlineFields(for: root)
        let (metadata, metadataChanged, assignedMetaId) = try ensureMetadata(for: root, in: context)
        if metadataChanged {
            didChange = true
        }
        if root.syncMetaId != assignedMetaId {
            root.syncMetaId = assignedMetaId
            didChange = true
        }
        metadata.updatedAt = max(metadata.updatedAt, root.updatedAt)
        return didChange
    }

    static func markCreated<Root: SyncTrackedRoot>(_ root: Root, in context: ModelContext) throws {
        root.createdAt = root.syncSeedDate
        root.updatedAt = root.createdAt
        root.soft_deleted = false
        root.applyLegacyDeleteBridge(false)
        let (metadata, _, assignedMetaId) = try ensureMetadata(for: root, in: context)
        root.syncMetaId = assignedMetaId
        metadata.localVersion = max(metadata.localVersion, 1)
        metadata.syncState = .pending
        metadata.lastErrorCode = nil
        metadata.lastErrorMessage = nil
        metadata.createdAt = root.createdAt
        metadata.updatedAt = root.updatedAt
    }

    static func markUpdated<Root: SyncTrackedRoot>(_ root: Root, in context: ModelContext) throws {
        _ = normalizeInlineFields(for: root)
        root.updatedAt = max(Date(), root.createdAt)
        let (metadata, _, assignedMetaId) = try ensureMetadata(for: root, in: context)
        root.syncMetaId = assignedMetaId
        metadata.localVersion = max(metadata.localVersion + 1, 1)
        metadata.syncState = .pending
        metadata.lastErrorCode = nil
        metadata.lastErrorMessage = nil
        metadata.updatedAt = root.updatedAt
    }

    static func markSoftDeleted<Root: SyncTrackedRoot>(_ root: Root, in context: ModelContext) throws {
        _ = normalizeInlineFields(for: root)
        root.soft_deleted = true
        root.applyLegacyDeleteBridge(true)
        root.updatedAt = max(Date(), root.createdAt)
        let (metadata, _, assignedMetaId) = try ensureMetadata(for: root, in: context)
        root.syncMetaId = assignedMetaId
        metadata.localVersion = max(metadata.localVersion + 1, 1)
        metadata.syncState = .pending
        metadata.lastErrorCode = nil
        metadata.lastErrorMessage = nil
        metadata.updatedAt = root.updatedAt
    }

    static func markRestored<Root: SyncTrackedRoot>(_ root: Root, in context: ModelContext) throws {
        _ = normalizeInlineFields(for: root)
        root.soft_deleted = false
        root.applyLegacyDeleteBridge(false)
        root.updatedAt = max(Date(), root.createdAt)
        let (metadata, _, assignedMetaId) = try ensureMetadata(for: root, in: context)
        root.syncMetaId = assignedMetaId
        metadata.localVersion = max(metadata.localVersion + 1, 1)
        metadata.syncState = .pending
        metadata.lastErrorCode = nil
        metadata.lastErrorMessage = nil
        metadata.updatedAt = root.updatedAt
    }

    private static func normalizeInlineFields<Root: SyncTrackedRoot>(for root: Root) -> Bool {
        var didChange = false
        let seedDate = root.syncSeedDate
        if root.createdAt > seedDate {
            root.createdAt = seedDate
            didChange = true
        }
        if root.updatedAt < root.createdAt {
            root.updatedAt = root.createdAt
            didChange = true
        }

        let effectiveDeleted = root.soft_deleted || (root.legacyDeleteBridgeValue ?? false)
        if root.soft_deleted != effectiveDeleted {
            root.soft_deleted = effectiveDeleted
            didChange = true
        }
        if root.legacyDeleteBridgeValue != nil, root.legacyDeleteBridgeValue != effectiveDeleted {
            root.applyLegacyDeleteBridge(effectiveDeleted)
            didChange = true
        }

        return didChange
    }

    private static func ensureMetadata<Root: SyncTrackedRoot>(
        for root: Root,
        in context: ModelContext
    ) throws -> (SyncMetadataItem, Bool, UUID) {
        let linkedItemId = root.id.uuidString.lowercased()

        if let syncMetaId = root.syncMetaId,
           let metadata = try fetchMetadata(by: syncMetaId, in: context) {
            var changed = false
            if metadata.linkedItemId != linkedItemId {
                metadata.linkedItemId = linkedItemId
                changed = true
            }
            if metadata.modelTypeRaw != Root.syncModelType.rawValue {
                metadata.modelTypeRaw = Root.syncModelType.rawValue
                changed = true
            }
            if metadata.createdAt > root.createdAt {
                metadata.createdAt = root.createdAt
                changed = true
            }
            if metadata.updatedAt < root.updatedAt {
                metadata.updatedAt = root.updatedAt
                changed = true
            }
            return (metadata, changed, syncMetaId)
        }

        if let metadata = try fetchMetadata(linkedItemId: linkedItemId, modelType: Root.syncModelType, in: context) {
            var changed = false
            if root.syncMetaId != metadata.id {
                changed = true
            }
            if metadata.createdAt > root.createdAt {
                metadata.createdAt = root.createdAt
                changed = true
            }
            if metadata.updatedAt < root.updatedAt {
                metadata.updatedAt = root.updatedAt
                changed = true
            }
            return (metadata, changed, metadata.id)
        }

        let metadataId = root.syncMetaId ?? UUID()
        let metadata = SyncMetadataItem(
            id: metadataId,
            linkedItemId: linkedItemId,
            modelType: Root.syncModelType,
            localVersion: 0,
            syncState: .pending,
            createdAt: root.createdAt,
            updatedAt: root.updatedAt
        )
        context.insert(metadata)
        return (metadata, true, metadataId)
    }

    private static func fetchMetadata(by id: UUID, in context: ModelContext) throws -> SyncMetadataItem? {
        let descriptor = FetchDescriptor<SyncMetadataItem>(
            predicate: #Predicate<SyncMetadataItem> { metadata in
                metadata.id == id
            }
        )
        return try context.fetch(descriptor).first
    }

    private static func fetchMetadata(
        linkedItemId: String,
        modelType: SyncModelType,
        in context: ModelContext
    ) throws -> SyncMetadataItem? {
        let modelTypeRaw = modelType.rawValue
        let descriptor = FetchDescriptor<SyncMetadataItem>(
            predicate: #Predicate<SyncMetadataItem> { metadata in
                metadata.linkedItemId == linkedItemId && metadata.modelTypeRaw == modelTypeRaw
            }
        )
        return try context.fetch(descriptor).first
    }
}
