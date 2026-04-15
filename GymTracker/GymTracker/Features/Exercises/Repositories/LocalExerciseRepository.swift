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
            guard let key = normalizedNpId(exercise.npId) else { continue }
            existingByNpId[key, default: []].append(exercise)
        }

        var inserted = 0
        var updated = 0
        var removed = 0

        for apiExercise in data {
            let npIdKey = normalizedNpId(apiExercise.id) ?? apiExercise.id.lowercased()
            let matches = existingByNpId[npIdKey] ?? []

            if matches.isEmpty {
                if allowInsert {
                    let newExercise = Exercise(from: apiExercise, userId: userId)
                    modelContext.insert(newExercise)
                    try SyncRootMetadataManager.markCreated(newExercise, in: modelContext)
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
                    applyApiPayload(apiExercise, to: exercise)
                    try SyncRootMetadataManager.markUpdated(exercise, in: modelContext)
                    updated += 1
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

            applyApiPayload(apiExercise, to: primary)
            try SyncRootMetadataManager.markUpdated(primary, in: modelContext)
            updated += 1

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
        } else {
            modelContext.insert(exercise)
            try SyncRootMetadataManager.markCreated(exercise, in: modelContext)
        }
        try modelContext.save()
    }

    func willArchiveOnDelete(_ exercise: Exercise) -> Bool {
        let hasPersistedHistory = (try? hasSessionHistory(exerciseID: exercise.id)) ?? false
        return !exercise.sessionEntries.isEmpty || hasPersistedHistory
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

    private func applyApiPayload(_ apiExercise: ExerciseDTO, to exercise: Exercise) {
        exercise.npId = apiExercise.id
        exercise.isUserCreated = false
        exercise.name = apiExercise.name
        exercise.type = ExerciseType.from(apiCategory: apiExercise.category).rawValue
        exercise.primary_muscles = apiExercise.primaryMuscles
        exercise.secondary_muscles = apiExercise.secondaryMuscles
        exercise.equipment = apiExercise.equipment
        exercise.category = apiExercise.category
        exercise.instructions = apiExercise.instructions
        if imagesHaveChanged(existing: exercise.images, incoming: apiExercise.images) {
            let oldCount = exercise.images?.count ?? 0
            let newCount = apiExercise.images.count
            print("Exercise image update: id=\(exercise.id), npId=\(apiExercise.id), oldCount=\(oldCount), newCount=\(newCount). Marking cachedMedia=false.")
            exercise.cachedMedia = false
        }
        exercise.images = apiExercise.images
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
