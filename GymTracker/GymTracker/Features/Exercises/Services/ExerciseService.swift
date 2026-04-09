//
//  ExerciseService.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftUI
import SwiftData
import Combine
internal import CoreData

class ExerciseService : ServiceBase, ObservableObject {
    struct NpIdMergeReport {
        let groupsMerged: Int
        let duplicatesRemoved: Int
    }

    @Published var exercises: [Exercise] = []
    @Published var archivedExercises: [Exercise] = []
    @Published var editingContent: String = ""
    @Published var editingExercise: Bool = false
    @Published var selectedExerciseType: ExerciseType = ExerciseType.weight
    
    // for api data

    @Published var apiExercises: [ExerciseDTO] = []

    private let apiHelper: API_Helper
    private let exerciseApi: ExerciseApi
    private var isLoadingApiExercises = false
    private var apiSyncedUserId: UUID?
    
    private struct ExerciseRelationshipCounts {
        let splitDays: Int
        let sessionEntries: Int

        var total: Int { splitDays + sessionEntries }
        var allZero: Bool { splitDays == 0 && sessionEntries == 0 }
    }

    override init(context: ModelContext) {
        let apiHelper = API_Helper()
        self.apiHelper = apiHelper
        self.exerciseApi = ExerciseApi(apiHelper: apiHelper)
        super.init(context: context)
    }

    override func loadFeature() {
        refreshExerciseLists()
        guard let userId = currentUser?.id else { return }
        guard apiSyncedUserId != userId else { return }
        Task {
            await self.loadApiExercises()
        }
    }
    
    func loadExercises() {
        guard let userId = currentUser?.id else {
            exercises = []
            return
        }

        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { exercise in
                exercise.user_id == userId && exercise.isArchived == false
            },
            sortBy: [SortDescriptor(\.name)]
        )

        do {
            exercises = try modelContext.fetch(descriptor)
            // verify exercises
            for exercise in exercises {
                print("\(exercise.name) \(exercise.type)")
            }
        } catch {
            exercises = []
        }
    }

    func loadArchivedExercises() {
        guard let userId = currentUser?.id else {
            archivedExercises = []
            return
        }

        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { exercise in
                exercise.user_id == userId && exercise.isArchived == true
            },
            sortBy: [SortDescriptor(\.name)]
        )

        do {
            archivedExercises = try modelContext.fetch(descriptor)
        } catch {
            archivedExercises = []
        }
    }

    func loadApiExercises() async {
        let userId: UUID
        guard let startedUserId = await MainActor.run(body: { () -> UUID? in
            guard !self.isLoadingApiExercises else { return nil }
            guard let userId = self.currentUser?.id else { return nil }
            self.isLoadingApiExercises = true
            return userId
        }) else {
            return
        }
        userId = startedUserId

        defer {
            Task { @MainActor in
                self.isLoadingApiExercises = false
            }
        }

        do {
            let data = try await exerciseApi.getExercises()
            let result = try await MainActor.run {
                try self.applyApiExercises(data, userId: userId)
            }
            await MainActor.run {
                self.loadExercises()
                self.loadArchivedExercises()
                self.apiSyncedUserId = userId
            }

            // TODO, only cache on launch
            await cacheMediaForUserExercises(userId: userId)
            print("Cached all non-user exercise thumbnails and GIFs.")
            print("Loaded \(data.count) exercises from API (\(result.inserted) new, \(result.updated) updated, \(result.removed) deduped)")
        } catch {
            print("Error loading API exercises: \(error)")
        }
    }

    @MainActor
    private func applyApiExercises(_ data: [ExerciseDTO], userId: UUID) throws -> (inserted: Int, updated: Int, removed: Int) {
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { exercise in
                exercise.user_id == userId
            }
        )
        let existingForUser = try modelContext.fetch(descriptor)
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
                modelContext.insert(Exercise(from: apiExercise, userId: userId))
                inserted += 1
                continue
            }

            let selection = preferredExercise(from: matches)
            if selection.isAmbiguous {
                print("Exercise dedupe skipped for npId=\(npIdKey): ambiguous primary exercise selection.")
                for exercise in matches where exercise.user_id == userId {
                    applyApiPayload(apiExercise, to: exercise)
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
            updated += 1

            var retained: [Exercise] = [primary]
            for duplicate in matches where duplicate.id != primary.id {
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

    @MainActor
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
        exercise.images = apiExercise.images
    }

    @MainActor
    private func mergeExerciseReferences(from duplicate: Exercise, to primary: Exercise, targetUserId: UUID) throws {
        guard duplicate.id != primary.id else { return }

        let duplicateId = duplicate.id

        // Re-link by direct fetch so merge does not depend on inverse array fault state.
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

    @MainActor
    private func exerciseRelationshipCounts(_ exercise: Exercise) -> ExerciseRelationshipCounts {
        ExerciseRelationshipCounts(
            splitDays: exercise.splits.count,
            sessionEntries: exercise.sessionEntries.count
        )
    }

    @MainActor
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

    @MainActor
    private func preferredExercise(from exercises: [Exercise]) -> (primary: Exercise?, isAmbiguous: Bool) {
        guard !exercises.isEmpty else { return (nil, false) }

        // Deterministic selection:
        // 1) Most total relationships (splitDays + sessionEntries)
        // 2) Oldest timestamp
        // 3) Lexicographically smallest UUID string
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

    @MainActor
    private func cacheMediaForUserExercises(userId: UUID) async {
        do {
            let cacheCandidates = try fetchExercisesForUser(userId: userId)
            for exercise in cacheCandidates {
                if (exercise.images == nil) { continue }
                if (exercise.cachedMedia == true) { continue }

                async let thumb = self.cacheThumbnail(for: exercise)
                async let gif = self.cacheGIF(for: exercise)
                _ = await (thumb, gif)

                exercise.cachedMedia = true
                try? self.modelContext.save()
            }
        } catch {
            print("Failed to load exercises for media caching: \(error)")
        }
    }

    private func normalizedNpId(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }

    @MainActor
    private func fetchExercisesForUser(userId: UUID) throws -> [Exercise] {
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { exercise in
                exercise.user_id == userId && exercise.isArchived == false
            },
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    func search(query: String) -> [Exercise] {
        print("searching exercise \(query)")
        guard !query.isEmpty else { return exercises }
        return exercises.filter { exercise in
            if exercise.name.localizedCaseInsensitiveContains(query) {
                return true
            }
            return (exercise.aliases ?? []).contains { alias in
                alias.localizedCaseInsensitiveContains(query)
            }
        }
    }

    func normalizedAliases(from rawValue: String) -> [String] {
        rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    @discardableResult
    func setAliases(for exercise: Exercise, aliases: [String]) -> Bool {
        exercise.aliases = Array(Set(aliases)).sorted()
        do {
            try modelContext.save()
            refreshExerciseLists()
            return true
        } catch {
            print("Failed to save exercise aliases: \(error)")
            return false
        }
    }
    
    func getUniquePrimaryMuscles() -> [String] {
        var muscles = Set<String>()
        for exercise in exercises {
            if let primaryMuscles = exercise.primary_muscles {
                for muscle in primaryMuscles {
                    muscles.insert(muscle)
                }
            }
        }
        return Array(muscles).sorted()
    }
    
    func getUniquePrimaryMuscles(searchQuery: String) -> [String] {
        var muscles = Set<String>()
        let filtered = exercises.filter { exercise in
            guard !searchQuery.isEmpty else { return true }
            return exercise.name.localizedCaseInsensitiveContains(searchQuery)
        }
        
        for exercise in filtered {
            if let primaryMuscles = exercise.primary_muscles {
                for muscle in primaryMuscles {
                    muscles.insert(muscle)
                }
            }
        }
        return Array(muscles).sorted()
    }
    
    func filterByMuscle(_ muscle: String) -> [Exercise] {
        guard !muscle.isEmpty else { return exercises }
        return exercises.filter { exercise in
            guard let primaryMuscles = exercise.primary_muscles else { return false }
            return primaryMuscles.contains(where: { $0.lowercased() == muscle.lowercased() })
        }
    }
    
    func addExercise() -> Exercise? {
        print("Adding")
        let trimmedName = editingContent.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return nil }
        guard let userId = currentUser?.id else { return nil }
        
        let newItem = Exercise(name: trimmedName, type: selectedExerciseType, user_id: userId)
        var failed = false
        
        withAnimation {
            modelContext.insert(newItem)
            
            do {
                try modelContext.save()
                // Clear and dismiss sheet after successful save
                editingExercise = false
                editingContent = ""
                refreshExerciseLists()
                selectedExerciseType = .weight

            } catch {
                print("Failed to save new split day: \(error)")
                failed=true
            }
        }
        
        if (failed==true) {
            return nil
        }
        return newItem;
    }
    
    func removeExercise(offsets: IndexSet) {
        print("not activating")
        for index in offsets {
            // Only safe when offsets map directly to the full exercises array.
            do {
                try delete(exercises[index])
            } catch {
                print("Failed to save after deletion: \(error)")
            }
        }
        refreshExerciseLists()
    }

    func removeExercises(_ exercisesToDelete: [Exercise]) {
        for exercise in exercisesToDelete {
            do {
                try delete(exercise)
            } catch {
                print("Failed to save after deletion: \(error)")
            }
        }
        refreshExerciseLists()
    }

    func addRestoredExercise(_ exercise: Exercise) {
        // For archived items, just unarchive
        if exercise.isArchived {
            exercise.isArchived = false
        } else {
            // For non-archived items that were deleted, re-insert and undelete
            modelContext.insert(exercise)
        }
        do {
            try modelContext.save()
            refreshExerciseLists()
        } catch {
            print("Failed to restore exercise: \(error)")
        }
    }

    func delete(_ exercise: Exercise) throws {
        let hasPersistedHistory = try hasSessionHistory(exerciseID: exercise.id)

        // If exercise has history → archive instead
        if !exercise.sessionEntries.isEmpty || hasPersistedHistory {
            exercise.isArchived = true

            // Remove from templates
            for split in Array(exercise.splits) {
                modelContext.delete(split)
            }

            try modelContext.save()
            return
        }

        // No history → mark as archived (soft delete) for undo support
        exercise.isArchived = true
        try modelContext.save()
    }

    func willArchiveOnDelete(_ exercise: Exercise) -> Bool {
        let hasPersistedHistory = (try? hasSessionHistory(exerciseID: exercise.id)) ?? false
        return !exercise.sessionEntries.isEmpty || hasPersistedHistory
    }

    func restore(_ exercise: Exercise) throws {
        exercise.isArchived = false
        try modelContext.save()
        refreshExerciseLists()
    }

    @MainActor
    func mergeExercisesWithSameNpId() throws -> NpIdMergeReport {
        guard let currentUserId = currentUser?.id else {
            return NpIdMergeReport(groupsMerged: 0, duplicatesRemoved: 0)
        }

        let allExercises = try modelContext.fetch(FetchDescriptor<Exercise>())

        var groupedByNpId: [String: [Exercise]] = [:]
        for exercise in allExercises {
            guard let npId = normalizedNpId(exercise.npId) else { continue }
            groupedByNpId[npId, default: []].append(exercise)
        }

        var groupsMerged = 0
        var duplicatesRemoved = 0

        for group in groupedByNpId.values where group.count > 1 {
            let currentUserMatches = group.filter { $0.user_id == currentUserId }
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

                try mergeExerciseReferences(from: duplicate, to: primary, targetUserId: currentUserId)

                if try exerciseRelationshipCounts(forExerciseId: duplicate.id).allZero {
                    modelContext.delete(duplicate)
                    duplicatesRemoved += 1
                    didMergeGroup = true
                }
            }

            primary.user_id = currentUserId
            primary.aliases = Array(aliases).sorted()

            if didMergeGroup {
                groupsMerged += 1
            }
        }

        if groupsMerged > 0 || duplicatesRemoved > 0 {
            try modelContext.save()
        }

        refreshExerciseLists()
        return NpIdMergeReport(groupsMerged: groupsMerged, duplicatesRemoved: duplicatesRemoved)
    }

    private func hasSessionHistory(exerciseID: UUID) throws -> Bool {
        let descriptor = FetchDescriptor<SessionEntry>(
            predicate: #Predicate<SessionEntry> { entry in
                entry.exercise.id == exerciseID
            }
        )
        return try !modelContext.fetch(descriptor).isEmpty
    }

    private func refreshExerciseLists() {
        loadExercises()
        loadArchivedExercises()
    }
}


extension ExerciseService {
    func thumbnailURL(for exercise: Exercise) -> URL? {
        guard
            let first = exercise.images?.first,
            let url = apiHelper.resolveMediaURL(first)
        else {
            print("Missing or invalid thumbnail URL for \(exercise.name)")
            return nil
        }

        print("Thumbnail for \(exercise.name) → \(url.absoluteString)")
        return url
    }

    func gifURL(for exercise: Exercise) -> URL? {
        guard
            let last = exercise.images?.last,
            let url = apiHelper.resolveMediaURL(last)
        else {
            print("⚠️ Missing or invalid GIF URL for \(exercise.name)")
            return nil
        }

        print("GIF for \(exercise.name) → \(url.absoluteString)")
        return url
    }

    /// Caches the thumbnail (.first image)
    func cacheThumbnail(for exercise: Exercise) async -> URL? {
        guard let url = self.thumbnailURL(for: exercise) else { return nil }
        do {
            return try await MediaCache.shared.fetch(url)
        } catch {
            print("⚠️ Failed to cache thumbnail for \(exercise.name): \(error)")
            return nil
        }
    }

    /// Caches the GIF (.last image)
    func cacheGIF(for exercise: Exercise) async -> URL? {
        guard let url = self.gifURL(for: exercise) else { return nil }
        do {
            return try await MediaCache.shared.fetch(url)
        } catch {
            print("⚠️ Failed to cache GIF for \(exercise.name): \(error)")
            return nil
        }
    }

    /// Checks if either thumbnail or GIF is already cached
    func hasCachedMedia(for exercise: Exercise) async -> (thumbnail: Bool, gif: Bool) {
        var result = (thumbnail: false, gif: false)
        
        if let thumbURL = self.thumbnailURL(for: exercise),
           await MediaCache.shared.cachedFile(for: thumbURL) != nil {
            result.thumbnail = true
        }
        
        if let gifURL = self.gifURL(for: exercise),
           await MediaCache.shared.cachedFile(for: gifURL) != nil {
            result.gif = true
        }
        
        return result
    }
}

extension API_Helper {
    func fetchExercises() async throws -> [ExerciseDTO] {
        let response: ListResponse<ExerciseDTO> = try await asyncRequestListData(route: APIRoute.exercises)
        return response.items
    }
}
