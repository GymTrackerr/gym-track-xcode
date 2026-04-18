//
//  LocalExerciseRepository.swift
//  GymTracker
//
//  Created by Codex on 2026-04-15.
//

import Foundation
import SwiftData

final class LocalExerciseRepository: ExerciseRepositoryProtocol {
    private struct ExerciseRelationshipCounts {
        let splitDays: Int
        let sessionEntries: Int

        var total: Int { splitDays + sessionEntries }
        var allZero: Bool { splitDays == 0 && sessionEntries == 0 }
    }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchActiveExercises(for userId: UUID) throws -> [Exercise] {
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { exercise in
                exercise.user_id == userId && exercise.soft_deleted == false && exercise.isArchived == false
            },
            sortBy: [SortDescriptor(\.name)]
        )
        let exercises = try modelContext.fetch(descriptor)
        if try SyncRootMetadataManager.prepareForRead(exercises, in: modelContext) {
            try modelContext.save()
        }
        return exercises
    }

    func fetchArchivedExercises(for userId: UUID) throws -> [Exercise] {
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { exercise in
                exercise.user_id == userId && (exercise.soft_deleted == true || exercise.isArchived == true)
            },
            sortBy: [SortDescriptor(\.name)]
        )
        let exercises = try modelContext.fetch(descriptor)
        if try SyncRootMetadataManager.prepareForRead(exercises, in: modelContext) {
            try modelContext.save()
        }
        return exercises
    }

    func applyCatalogExercises(
        _ data: [ExerciseDTO],
        for userId: UUID,
        allowInsert: Bool
    ) throws -> (inserted: Int, updated: Int, removed: Int) {
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { exercise in
                exercise.user_id == userId
            }
        )
        let existingForUser = try modelContext.fetch(descriptor)
        if try SyncRootMetadataManager.prepareForRead(existingForUser, in: modelContext) {
            try modelContext.save()
        }
        var existingByNpId: [String: [Exercise]] = [:]
        for exercise in existingForUser {
            guard exercise.isUserCreated == false else { continue }
            guard let key = normalizedNpId(exercise.npId) else { continue }
            existingByNpId[key, default: []].append(exercise)
        }

        var inserted = 0
        var updated = 0
        var removed = 0
        var remoteAppliedExercises: [Exercise] = []

        for apiExercise in data {
            let npIdKey = normalizedNpId(apiExercise.id) ?? apiExercise.id.lowercased()
            let matches = existingByNpId[npIdKey] ?? []

            if matches.isEmpty {
                if allowInsert {
                    let newExercise = Exercise(from: apiExercise, userId: userId)
                    newExercise.isArchived = false
                    newExercise.soft_deleted = false
                    modelContext.insert(newExercise)
                    remoteAppliedExercises.append(newExercise)
                    inserted += 1
                } else {
                    print("Update-only sync skipped insert for npId=\(npIdKey).")
                }
                continue
            }

            let selection = preferredExercise(from: matches)
            if selection.isAmbiguous {
                print("Exercise dedupe skipped for npId=\(npIdKey): ambiguous primary exercise selection.")
                for exercise in matches where exercise.user_id == userId {
                    if applyApiPayload(apiExercise, to: exercise) {
                        updated += 1
                    }
                    remoteAppliedExercises.append(exercise)
                }
                existingByNpId[npIdKey] = matches
                continue
            }
            guard let primary = selection.primary else {
                print("Exercise dedupe skipped for npId=\(npIdKey): no valid primary candidate.")
                continue
            }
            guard primary.user_id == userId else {
                print("Exercise dedupe skipped for npId=\(npIdKey): primary owner mismatch.")
                continue
            }

            if applyApiPayload(apiExercise, to: primary) {
                updated += 1
            }
            remoteAppliedExercises.append(primary)

            var retained: [Exercise] = [primary]
            for duplicate in matches where duplicate.id != primary.id {
                if imagesHaveChanged(existing: duplicate.images, incoming: apiExercise.images) {
                    let oldCount = duplicate.images?.count ?? 0
                    let newCount = apiExercise.images.count
                    print("Exercise image update (duplicate retained): id=\(duplicate.id), npId=\(apiExercise.id), oldCount=\(oldCount), newCount=\(newCount). Marking cachedMedia=false.")
                    duplicate.images = apiExercise.images
                    duplicate.cachedMedia = false
                }

                guard duplicate.user_id == userId else {
                    print("Exercise dedupe skipped for \(duplicate.id): duplicate owner mismatch.")
                    retained.append(duplicate)
                    continue
                }

                try mergeExerciseReferences(from: duplicate, to: primary, targetUserId: userId)
                let relationshipCounts = try exerciseRelationshipCounts(forExerciseId: duplicate.id)
                if relationshipCounts.allZero {
                    modelContext.delete(duplicate)
                    removed += 1
                } else {
                    print("Exercise dedupe skipped for \(duplicate.id): still linked (splits=\(relationshipCounts.splitDays), entries=\(relationshipCounts.sessionEntries)).")
                    retained.append(duplicate)
                }
            }
            existingByNpId[npIdKey] = retained
        }

        if inserted > 0 || updated > 0 || removed > 0 {
            try modelContext.save()
        }
        try markRemoteExercisesAsSynced(remoteAppliedExercises)
        return (inserted, updated, removed)
    }

    func applyCatalogOverlays(
        _ data: [GymTrackerCatalogOverlayDTO],
        for userId: UUID
    ) throws -> Int {
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { exercise in
                exercise.user_id == userId
            }
        )
        let existingForUser = try modelContext.fetch(descriptor)
        if try SyncRootMetadataManager.prepareForRead(existingForUser, in: modelContext) {
            try modelContext.save()
        }

        var existingByNpId: [String: [Exercise]] = [:]
        for exercise in existingForUser {
            guard exercise.isUserCreated == false else { continue }
            guard let key = normalizedNpId(exercise.npId) else { continue }
            existingByNpId[key, default: []].append(exercise)
        }

        var updated = 0
        var remoteAppliedExercises: [Exercise] = []

        for overlay in data {
            let npIdKey = normalizedNpId(overlay.npId) ?? overlay.npId.lowercased()
            let matches = existingByNpId[npIdKey] ?? []

            for exercise in matches where exercise.user_id == userId {
                if applyCatalogOverlayPayload(overlay, to: exercise) {
                    updated += 1
                }
                remoteAppliedExercises.append(exercise)
            }
        }

        if updated > 0 {
            try modelContext.save()
        }
        try markRemoteExercisesAsSynced(remoteAppliedExercises)
        return updated
    }

    func applyRemoteUserExercises(
        _ data: [GymTrackerExerciseDTO],
        for userId: UUID
    ) throws -> (inserted: Int, updated: Int, removed: Int) {
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { exercise in
                exercise.user_id == userId
            }
        )
        let existingForUser = try modelContext.fetch(descriptor)
        if try SyncRootMetadataManager.prepareForRead(existingForUser, in: modelContext) {
            try modelContext.save()
        }

        var existingById: [String: Exercise] = [:]
        for exercise in existingForUser where exercise.isUserCreated {
            existingById[exercise.id.uuidString.lowercased()] = exercise
        }

        var inserted = 0
        var updated = 0
        var removed = 0
        var remoteAppliedExercises: [Exercise] = []

        for remoteExercise in data {
            guard UUID(uuidString: remoteExercise.id) != nil else { continue }
            let key = remoteExercise.id.lowercased()
            if let existing = existingById[key] {
                if applyGymTrackerPayload(remoteExercise, to: existing, defaultUserId: userId) {
                    updated += 1
                }
                remoteAppliedExercises.append(existing)
            } else {
                let created = Exercise(from: remoteExercise, userId: userId)
                created.isUserCreated = true
                created.npId = nil
                _ = applyRemoteTimestamps(
                    createdAt: remoteExercise.createdAt,
                    updatedAt: remoteExercise.updatedAt,
                    deletedAt: remoteExercise.deletedAt,
                    to: created
                )
                modelContext.insert(created)
                remoteAppliedExercises.append(created)
                inserted += 1
            }
        }

        if inserted > 0 || updated > 0 || removed > 0 {
            try modelContext.save()
        }
        try markRemoteExercisesAsSynced(remoteAppliedExercises)
        return (inserted, updated, removed)
    }

    func createExercise(name: String, type: ExerciseType, userId: UUID) throws -> Exercise {
        let newItem = Exercise(name: name, type: type, user_id: userId)
        modelContext.insert(newItem)
        try SyncRootMetadataManager.markCreated(newItem, in: modelContext)
        try modelContext.save()
        return newItem
    }

    func setAliases(_ aliases: [String], for exercise: Exercise) throws {
        exercise.aliases = Array(Set(aliases)).sorted()
        try SyncRootMetadataManager.markUpdated(exercise, in: modelContext)
        try modelContext.save()
    }

    func delete(_ exercise: Exercise) throws {
        let hasPersistedHistory = try hasSessionHistory(exerciseID: exercise.id)

        if !exercise.sessionEntries.isEmpty || hasPersistedHistory {
            for split in Array(exercise.splits) {
                modelContext.delete(split)
            }
            try SyncRootMetadataManager.markSoftDeleted(exercise, in: modelContext)
            try modelContext.save()
            return
        }

        try SyncRootMetadataManager.markSoftDeleted(exercise, in: modelContext)
        try modelContext.save()
    }

    func restore(_ exercise: Exercise) throws {
        try SyncRootMetadataManager.markRestored(exercise, in: modelContext)
        try modelContext.save()
    }

    func reinsertOrRestore(_ exercise: Exercise) throws {
        if exercise.isArchived {
            try SyncRootMetadataManager.markRestored(exercise, in: modelContext)
            try modelContext.save()
        } else {
            modelContext.insert(exercise)
            try SyncRootMetadataManager.markCreated(exercise, in: modelContext)
            try modelContext.save()
        }
    }

    func willArchiveOnDelete(_ exercise: Exercise) -> Bool {
        let hasPersistedHistory = (try? hasSessionHistory(exerciseID: exercise.id)) ?? false
        return !exercise.sessionEntries.isEmpty || hasPersistedHistory
    }

    func hideCatalogExercises(for userId: UUID) throws -> CatalogDisableResult {
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { exercise in
                exercise.user_id == userId
            }
        )
        let existingForUser = try modelContext.fetch(descriptor)

        var hiddenCount = 0
        var deletedCount = 0
        var hiddenNpIds: [String] = []
        let timestamp = Date()

        for exercise in existingForUser where exercise.isUserCreated == false {
            let relationshipCounts = try exerciseRelationshipCounts(forExerciseId: exercise.id)

            if relationshipCounts.allZero {
                modelContext.delete(exercise)
                deletedCount += 1
                continue
            }

            let wasHidden = exercise.isArchived || exercise.soft_deleted
            if wasHidden {
                continue
            }

            exercise.isArchived = true
            exercise.soft_deleted = true
            exercise.updatedAt = max(timestamp, exercise.createdAt)
            if let npId = normalizedNpId(exercise.npId) {
                hiddenNpIds.append(npId)
            }
            hiddenCount += 1
        }

        if hiddenCount > 0 || deletedCount > 0 {
            try modelContext.save()
        }

        return CatalogDisableResult(
            hiddenNpIds: Array(Set(hiddenNpIds)).sorted(),
            hiddenCount: hiddenCount,
            deletedCount: deletedCount
        )
    }

    func restoreCatalogExercises(withNpIds npIds: [String], for userId: UUID) throws -> Int {
        let normalizedNpIds = Set(
            npIds.compactMap { normalizedNpId($0) }
        )
        guard normalizedNpIds.isEmpty == false else { return 0 }

        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { exercise in
                exercise.user_id == userId
            }
        )
        let existingForUser = try modelContext.fetch(descriptor)

        var restoredCount = 0
        let timestamp = Date()

        for exercise in existingForUser where exercise.isUserCreated == false {
            guard let npId = normalizedNpId(exercise.npId) else { continue }
            guard normalizedNpIds.contains(npId) else { continue }

            let wasHidden = exercise.isArchived || exercise.soft_deleted
            guard wasHidden else { continue }

            exercise.isArchived = false
            exercise.soft_deleted = false
            exercise.updatedAt = max(timestamp, exercise.createdAt)
            restoredCount += 1
        }

        if restoredCount > 0 {
            try modelContext.save()
        }

        return restoredCount
    }

    func mergeExercisesWithSameNpId(for userId: UUID) throws -> ExerciseNpIdMergeReport {
        let allExercises = try modelContext.fetch(FetchDescriptor<Exercise>())

        var groupedByNpId: [String: [Exercise]] = [:]
        for exercise in allExercises {
            guard let npId = normalizedNpId(exercise.npId) else { continue }
            groupedByNpId[npId, default: []].append(exercise)
        }

        var groupsMerged = 0
        var duplicatesRemoved = 0

        for group in groupedByNpId.values where group.count > 1 {
            let currentUserMatches = group.filter { $0.user_id == userId }
            guard !currentUserMatches.isEmpty else { continue }

            let selection = preferredExercise(from: currentUserMatches)
            guard let primary = selection.primary, !selection.isAmbiguous else { continue }

            var aliases = Set((primary.aliases ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            var didMergeGroup = false

            for duplicate in group where duplicate.id != primary.id {
                for alias in duplicate.aliases ?? [] {
                    let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        aliases.insert(trimmed)
                    }
                }

                try mergeExerciseReferences(from: duplicate, to: primary, targetUserId: userId)

                if try exerciseRelationshipCounts(forExerciseId: duplicate.id).allZero {
                    modelContext.delete(duplicate)
                    duplicatesRemoved += 1
                    didMergeGroup = true
                }
            }

            primary.user_id = userId
            primary.aliases = Array(aliases).sorted()
            try SyncRootMetadataManager.markUpdated(primary, in: modelContext)

            if didMergeGroup {
                groupsMerged += 1
            }
        }

        if groupsMerged > 0 || duplicatesRemoved > 0 {
            try modelContext.save()
        }

        return ExerciseNpIdMergeReport(groupsMerged: groupsMerged, duplicatesRemoved: duplicatesRemoved)
    }

    func saveChanges() throws {
        try modelContext.save()
    }

    @discardableResult
    private func applyApiPayload(_ apiExercise: ExerciseDTO, to exercise: Exercise) -> Bool {
        var didChange = false
        let normalizedNpIdValue = normalizedNpId(apiExercise.id) ?? apiExercise.id
        if normalizedNpId(exercise.npId) != normalizedNpIdValue.lowercased() {
            exercise.npId = apiExercise.id
            didChange = true
        }
        if exercise.isUserCreated {
            exercise.isUserCreated = false
            didChange = true
        }
        if exercise.name != apiExercise.name {
            exercise.name = apiExercise.name
            didChange = true
        }
        let resolvedType = ExerciseType.from(apiCategory: apiExercise.category).rawValue
        if exercise.type != resolvedType {
            exercise.type = resolvedType
            didChange = true
        }
        if exercise.primary_muscles != apiExercise.primaryMuscles {
            exercise.primary_muscles = apiExercise.primaryMuscles
            didChange = true
        }
        if exercise.secondary_muscles != apiExercise.secondaryMuscles {
            exercise.secondary_muscles = apiExercise.secondaryMuscles
            didChange = true
        }
        if exercise.equipment != apiExercise.equipment {
            exercise.equipment = apiExercise.equipment
            didChange = true
        }
        if exercise.category != apiExercise.category {
            exercise.category = apiExercise.category
            didChange = true
        }
        if exercise.instructions != apiExercise.instructions {
            exercise.instructions = apiExercise.instructions
            didChange = true
        }
        if imagesHaveChanged(existing: exercise.images, incoming: apiExercise.images) {
            let oldCount = exercise.images?.count ?? 0
            let newCount = apiExercise.images.count
            print("Exercise image update: id=\(exercise.id), npId=\(apiExercise.id), oldCount=\(oldCount), newCount=\(newCount). Marking cachedMedia=false.")
            exercise.cachedMedia = false
            didChange = true
        }
        if exercise.images != apiExercise.images {
            exercise.images = apiExercise.images
            didChange = true
        }
        if exercise.isArchived {
            exercise.isArchived = false
            didChange = true
        }
        if exercise.soft_deleted {
            exercise.soft_deleted = false
            didChange = true
        }

        return didChange
    }

    @discardableResult
    private func applyGymTrackerPayload(
        _ dto: GymTrackerExerciseDTO,
        to exercise: Exercise,
        defaultUserId: UUID
    ) -> Bool {
        var didChange = false

        if exercise.isUserCreated != true {
            exercise.isUserCreated = true
            didChange = true
        }

        if exercise.user_id != defaultUserId {
            exercise.user_id = defaultUserId
            didChange = true
        }

        if exercise.name != dto.name {
            exercise.name = dto.name
            didChange = true
        }
        let resolvedType = ExerciseType.from(apiCategory: dto.type).rawValue
        if exercise.type != resolvedType {
            exercise.type = resolvedType
            didChange = true
        }
        if exercise.aliases != dto.aliases {
            exercise.aliases = dto.aliases
            didChange = true
        }
        if exercise.primary_muscles != dto.primaryMuscles {
            exercise.primary_muscles = dto.primaryMuscles
            didChange = true
        }
        if exercise.secondary_muscles != dto.secondaryMuscles {
            exercise.secondary_muscles = dto.secondaryMuscles
            didChange = true
        }
        if exercise.equipment != dto.equipment {
            exercise.equipment = dto.equipment
            didChange = true
        }
        if exercise.category != dto.category {
            exercise.category = dto.category
            didChange = true
        }
        if exercise.instructions != dto.instructions {
            exercise.instructions = dto.instructions
            didChange = true
        }
        if imagesHaveChanged(existing: exercise.images, incoming: dto.images) {
            exercise.cachedMedia = false
            didChange = true
        }
        if exercise.images != dto.images {
            exercise.images = dto.images
            didChange = true
        }

        let archived = dto.isArchived
        if exercise.isArchived != archived {
            exercise.isArchived = archived
            didChange = true
        }
        if exercise.soft_deleted != archived {
            exercise.soft_deleted = archived
            didChange = true
        }

        if applyRemoteTimestamps(
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            deletedAt: dto.deletedAt,
            to: exercise
        ) {
            didChange = true
        }

        return didChange
    }

    @discardableResult
    private func applyCatalogOverlayPayload(
        _ dto: GymTrackerCatalogOverlayDTO,
        to exercise: Exercise
    ) -> Bool {
        var didChange = false
        let aliases = normalizedAliases(dto.aliases)
        if exercise.aliases != aliases {
            exercise.aliases = aliases
            didChange = true
        }

        if exercise.isArchived != dto.hidden {
            exercise.isArchived = dto.hidden
            didChange = true
        }

        if exercise.soft_deleted != dto.hidden {
            exercise.soft_deleted = dto.hidden
            didChange = true
        }

        if let updatedAt = parsedRemoteDate(dto.updatedAt) {
            let resolvedUpdatedAt = max(updatedAt, exercise.createdAt)
            if exercise.updatedAt != resolvedUpdatedAt {
                exercise.updatedAt = resolvedUpdatedAt
                didChange = true
            }
        }

        return didChange
    }

    @discardableResult
    private func applyRemoteTimestamps(
        createdAt rawCreatedAt: String?,
        updatedAt rawUpdatedAt: String?,
        deletedAt rawDeletedAt: String?,
        to exercise: Exercise
    ) -> Bool {
        var didChange = false

        if let createdAt = parsedRemoteDate(rawCreatedAt) {
            if exercise.createdAt != createdAt {
                exercise.createdAt = createdAt
                didChange = true
            }
            if exercise.timestamp != createdAt {
                exercise.timestamp = createdAt
                didChange = true
            }
        }

        let remoteUpdatedAt =
            parsedRemoteDate(rawUpdatedAt) ??
            parsedRemoteDate(rawDeletedAt) ??
            parsedRemoteDate(rawCreatedAt)

        if let remoteUpdatedAt {
            let resolvedUpdatedAt = max(remoteUpdatedAt, exercise.createdAt)
            if exercise.updatedAt != resolvedUpdatedAt {
                exercise.updatedAt = resolvedUpdatedAt
                didChange = true
            }
        }

        return didChange
    }

    private func markRemoteExercisesAsSynced(_ exercises: [Exercise]) throws {
        let uniqueExercises = deduplicatedExercises(exercises)
        guard uniqueExercises.isEmpty == false else { return }

        _ = try SyncRootMetadataManager.prepareForRead(uniqueExercises, in: modelContext)
        let modelTypeRaw = SyncModelType.exercise.rawValue

        for exercise in uniqueExercises {
            let linkedItemId = exercise.syncLinkedItemId
            let descriptor = FetchDescriptor<SyncMetadataItem>(
                predicate: #Predicate<SyncMetadataItem> { metadata in
                    metadata.modelTypeRaw == modelTypeRaw &&
                    metadata.linkedItemId == linkedItemId
                }
            )

            guard let metadata = try modelContext.fetch(descriptor).first else { continue }
            let syncedAt = max(exercise.updatedAt, exercise.createdAt)
            metadata.syncState = .synced
            metadata.lastSyncedAt = syncedAt
            metadata.updatedAt = syncedAt
            metadata.lastErrorCode = nil
            metadata.lastErrorMessage = nil
        }

        try modelContext.save()
    }

    private func mergeExerciseReferences(from duplicate: Exercise, to primary: Exercise, targetUserId: UUID) throws {
        guard duplicate.id != primary.id else { return }

        let duplicateId = duplicate.id

        let splitDescriptor = FetchDescriptor<ExerciseSplitDay>(
            predicate: #Predicate<ExerciseSplitDay> { split in
                split.exercise.id == duplicateId
            }
        )
        let splits = try modelContext.fetch(splitDescriptor)
        for split in splits {
            split.exercise = primary
            split.routine.user_id = targetUserId
            if !primary.splits.contains(where: { $0.id == split.id }) {
                primary.splits.append(split)
            }
            if !split.routine.exerciseSplits.contains(where: { $0.id == split.id }) {
                split.routine.exerciseSplits.append(split)
            }
        }

        let entryDescriptor = FetchDescriptor<SessionEntry>(
            predicate: #Predicate<SessionEntry> { entry in
                entry.exercise.id == duplicateId
            }
        )
        let entries = try modelContext.fetch(entryDescriptor)
        for entry in entries {
            entry.exercise = primary
            entry.session.user_id = targetUserId
            entry.session.routine?.user_id = targetUserId
            if !primary.sessionEntries.contains(where: { $0.id == entry.id }) {
                primary.sessionEntries.append(entry)
            }
        }
    }

    private func exerciseRelationshipCounts(_ exercise: Exercise) -> ExerciseRelationshipCounts {
        ExerciseRelationshipCounts(
            splitDays: exercise.splits.count,
            sessionEntries: exercise.sessionEntries.count
        )
    }

    private func exerciseRelationshipCounts(forExerciseId exerciseId: UUID) throws -> ExerciseRelationshipCounts {
        let splitDescriptor = FetchDescriptor<ExerciseSplitDay>(
            predicate: #Predicate<ExerciseSplitDay> { split in
                split.exercise.id == exerciseId
            }
        )
        let entryDescriptor = FetchDescriptor<SessionEntry>(
            predicate: #Predicate<SessionEntry> { entry in
                entry.exercise.id == exerciseId
            }
        )

        return ExerciseRelationshipCounts(
            splitDays: try modelContext.fetch(splitDescriptor).count,
            sessionEntries: try modelContext.fetch(entryDescriptor).count
        )
    }

    private func preferredExercise(from exercises: [Exercise]) -> (primary: Exercise?, isAmbiguous: Bool) {
        guard !exercises.isEmpty else { return (nil, false) }

        let sorted = exercises.sorted { lhs, rhs in
            let lhsCounts = exerciseRelationshipCounts(lhs)
            let rhsCounts = exerciseRelationshipCounts(rhs)
            if lhsCounts.total != rhsCounts.total {
                return lhsCounts.total > rhsCounts.total
            }
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        guard let first = sorted.first else { return (nil, false) }
        let topCounts = exerciseRelationshipCounts(first)
        let topBucket = sorted.filter {
            let counts = exerciseRelationshipCounts($0)
            return counts.total == topCounts.total && $0.timestamp == first.timestamp
        }
        if topBucket.count > 1 {
            let distinctIds = Set(topBucket.map(\.id))
            if distinctIds.count == 1 {
                return (nil, true)
            }
        }
        return (first, false)
    }

    private func hasSessionHistory(exerciseID: UUID) throws -> Bool {
        let descriptor = FetchDescriptor<SessionEntry>(
            predicate: #Predicate<SessionEntry> { entry in
                entry.exercise.id == exerciseID
            }
        )
        return try !modelContext.fetch(descriptor).isEmpty
    }

    private func normalizedNpId(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }

    private func normalizedAliases(_ aliases: [String]) -> [String] {
        Array(
            Set(
                aliases
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted()
    }

    private func deduplicatedExercises(_ exercises: [Exercise]) -> [Exercise] {
        var seenIds = Set<UUID>()
        var uniqueExercises: [Exercise] = []

        for exercise in exercises where seenIds.insert(exercise.id).inserted {
            uniqueExercises.append(exercise)
        }

        return uniqueExercises
    }

    private func parsedRemoteDate(_ value: String?) -> Date? {
        guard let value else { return nil }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = fractionalFormatter.date(from: value) {
            return parsed
        }

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        return fallbackFormatter.date(from: value)
    }

    private func imagesHaveChanged(existing: [String]?, incoming: [String]) -> Bool {
        let normalizedExisting = (existing ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let normalizedIncoming = incoming
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return normalizedExisting != normalizedIncoming
    }
}
