//
//  SyncQueueStore.swift
//  GymTracker
//
//  Created by Codex on 2026-04-15.
//

import Foundation
import SwiftData

final class SyncQueueStore {
    private enum CoalescedMutation {
        case createNew
        case updateExisting(operation: SyncQueueOperation)
        case deleteExistingAndSkipNew
    }

    private let modelContext: ModelContext
    private var onQueueChange: (() -> Void)?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func setQueueChangeHandler(_ handler: @escaping () -> Void) {
        onQueueChange = handler
    }

    @discardableResult
    func enqueueMutation(
        modelType: SyncModelType,
        linkedItemId: String,
        operation: SyncQueueOperation,
        payloadSnapshotData: Data?,
        dependencyKey: String? = nil,
        priority: Int = 100,
        requiresAuth: Bool = true
    ) throws -> SyncQueueItem? {
        let openItems = try fetchOpenItems(modelType: modelType, linkedItemId: linkedItemId)
        let primaryExisting = openItems.min(by: { $0.createdAt < $1.createdAt })
        let timestamp = Date()

        if let primaryExisting {
            switch coalescedMutation(existing: primaryExisting.operation ?? .update, incoming: operation) {
            case .createNew:
                break
            case .updateExisting(let resolvedOperation):
                primaryExisting.operation = resolvedOperation
                primaryExisting.payloadSnapshotData = payloadSnapshotData
                primaryExisting.dependencyKey = dependencyKey ?? primaryExisting.dependencyKey
                primaryExisting.priority = min(primaryExisting.priority, priority)
                primaryExisting.status = .queued
                primaryExisting.attemptCount = 0
                primaryExisting.nextAttemptAt = timestamp
                primaryExisting.lastAttemptAt = nil
                primaryExisting.lastErrorCode = nil
                primaryExisting.lastErrorMessage = nil
                primaryExisting.requiresAuth = requiresAuth
                primaryExisting.updatedAt = timestamp

                removeDuplicateOpenItems(openItems, keeping: primaryExisting)
                try modelContext.save()
                onQueueChange?()
                return primaryExisting
            case .deleteExistingAndSkipNew:
                modelContext.delete(primaryExisting)
                removeDuplicateOpenItems(openItems, keeping: nil)
                try modelContext.save()
                onQueueChange?()
                return nil
            }
        }

        let newItem = SyncQueueItem(
            modelType: modelType,
            linkedItemId: linkedItemId,
            operation: operation,
            payloadSnapshotData: payloadSnapshotData,
            dependencyKey: dependencyKey,
            priority: priority,
            status: .queued,
            requiresAuth: requiresAuth,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        modelContext.insert(newItem)
        try modelContext.save()
        onQueueChange?()
        return newItem
    }

    func nextReadyItem(
        referenceDate: Date = Date()
    ) throws -> SyncQueueItem? {
        let queuedRaw = SyncQueueStatus.queued.rawValue
        let retryRaw = SyncQueueStatus.retryScheduled.rawValue
        var descriptor = FetchDescriptor<SyncQueueItem>(
            predicate: #Predicate<SyncQueueItem> { item in
                (item.statusRaw == queuedRaw || item.statusRaw == retryRaw) && item.nextAttemptAt <= referenceDate
            },
            sortBy: [
                SortDescriptor(\.priority, order: .forward),
                SortDescriptor(\.createdAt, order: .forward)
            ]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func markInFlight(_ item: SyncQueueItem, at timestamp: Date = Date()) throws {
        item.status = .inFlight
        item.lastAttemptAt = timestamp
        item.updatedAt = timestamp
        try modelContext.save()
    }

    func markRetryScheduled(
        _ item: SyncQueueItem,
        errorCode: String?,
        errorMessage: String?,
        at timestamp: Date = Date(),
        maxAttempts: Int = 10
    ) throws {
        item.attemptCount += 1
        item.lastAttemptAt = timestamp
        item.lastErrorCode = errorCode
        item.lastErrorMessage = errorMessage
        item.updatedAt = timestamp

        if item.attemptCount >= maxAttempts {
            item.status = .deadLetter
        } else {
            item.status = .retryScheduled
            item.nextAttemptAt = timestamp.addingTimeInterval(backoffDelay(forAttempt: item.attemptCount))
        }

        try modelContext.save()
    }

    func remove(_ item: SyncQueueItem) throws {
        modelContext.delete(item)
        try modelContext.save()
    }

    func markDeadLetter(
        _ item: SyncQueueItem,
        errorCode: String?,
        errorMessage: String?,
        at timestamp: Date = Date()
    ) throws {
        item.status = .deadLetter
        item.lastAttemptAt = timestamp
        item.lastErrorCode = errorCode
        item.lastErrorMessage = errorMessage
        item.updatedAt = timestamp
        try modelContext.save()
    }

    func purgeDeadLetters(olderThan cutoffDate: Date) throws {
        let deadLetterRaw = SyncQueueStatus.deadLetter.rawValue
        let descriptor = FetchDescriptor<SyncQueueItem>(
            predicate: #Predicate<SyncQueueItem> { item in
                item.statusRaw == deadLetterRaw && item.updatedAt < cutoffDate
            }
        )
        let items = try modelContext.fetch(descriptor)
        guard items.isEmpty == false else { return }

        for item in items {
            modelContext.delete(item)
        }
        try modelContext.save()
    }

    private func fetchOpenItems(
        modelType: SyncModelType,
        linkedItemId: String
    ) throws -> [SyncQueueItem] {
        let modelTypeRaw = modelType.rawValue
        let deadLetterRaw = SyncQueueStatus.deadLetter.rawValue

        let descriptor = FetchDescriptor<SyncQueueItem>(
            predicate: #Predicate<SyncQueueItem> { item in
                item.modelTypeRaw == modelTypeRaw && item.linkedItemId == linkedItemId && item.statusRaw != deadLetterRaw
            }
        )
        return try modelContext.fetch(descriptor)
    }

    private func removeDuplicateOpenItems(_ items: [SyncQueueItem], keeping keptItem: SyncQueueItem?) {
        for item in items where item.id != keptItem?.id {
            modelContext.delete(item)
        }
    }

    private func coalescedMutation(
        existing: SyncQueueOperation,
        incoming: SyncQueueOperation
    ) -> CoalescedMutation {
        switch (existing, incoming) {
        case (.create, .update):
            return .updateExisting(operation: .create)
        case (.create, .softDelete):
            return .deleteExistingAndSkipNew
        case (.softDelete, .restore):
            return .deleteExistingAndSkipNew
        case (.create, .restore):
            return .updateExisting(operation: .create)
        case (.restore, .update):
            return .updateExisting(operation: .restore)
        case (.softDelete, .update):
            return .updateExisting(operation: .softDelete)
        default:
            return .updateExisting(operation: incoming)
        }
    }

    private func backoffDelay(forAttempt attempt: Int) -> TimeInterval {
        let cappedAttempt = min(max(attempt, 1), 10)
        let baseDelay = pow(2.0, Double(cappedAttempt))
        let cappedDelay = min(baseDelay, 15 * 60)
        let jitter = Double.random(in: 0.8...1.2)
        return cappedDelay * jitter
    }
}
