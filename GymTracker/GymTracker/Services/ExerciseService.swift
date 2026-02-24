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
    @Published var exercises: [Exercise] = []
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
        self.loadExercises()
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
                exercise.user_id == userId
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

                mergeExerciseReferences(from: duplicate, to: primary, currentUserId: userId)
                let relationshipCounts = exerciseRelationshipCounts(duplicate)
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
        exercise.primary_muscles = apiExercise.primaryMuscles
        exercise.secondary_muscles = apiExercise.secondaryMuscles
        exercise.equipment = apiExercise.equipment
        exercise.category = apiExercise.category
        exercise.instructions = apiExercise.instructions
        exercise.images = apiExercise.images
    }

    @MainActor
    private func mergeExerciseReferences(from duplicate: Exercise, to primary: Exercise, currentUserId: UUID) {
        guard duplicate.id != primary.id else { return }
        guard duplicate.user_id == currentUserId, primary.user_id == currentUserId else {
            print("Skipped cross-user merge attempt for exercise \(duplicate.id).")
            return
        }

        // Exercise has two inverse relationships today: splits and sessionEntries.
        for split in duplicate.splits where split.exercise.id == duplicate.id {
            split.exercise = primary
            if !primary.splits.contains(where: { $0.id == split.id }) {
                primary.splits.append(split)
            }
        }

        for entry in duplicate.sessionEntries where entry.exercise.id == duplicate.id {
            entry.exercise = primary
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
                exercise.user_id == userId
            },
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    func search(query: String) -> [Exercise] {
        print("searching exercise \(query)")
        guard !query.isEmpty else { return exercises }
        return exercises.filter { $0.name.localizedCaseInsensitiveContains(query) }
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
                loadExercises()
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
            modelContext.delete(exercises[index])
        }

        do {
            try modelContext.save()
            loadExercises()
        } catch {
            print("Failed to save after deletion: \(error)")
        }
    }

    func removeExercises(_ exercisesToDelete: [Exercise]) {
        for exercise in exercisesToDelete {
            modelContext.delete(exercise)
        }

        do {
            try modelContext.save()
            loadExercises()
        } catch {
            print("Failed to save after deletion: \(error)")
        }
    }
}


extension ExerciseService {
    func thumbnailURL(for exercise: Exercise) -> URL? {
        guard
            let first = exercise.images?.first,
            let baseURL = URL(string: apiHelper.apiData.getURL().replacingOccurrences(of: "/v1", with: "")),
            let url = URL(string: first, relativeTo: baseURL)
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
            let baseURL = URL(string: apiHelper.apiData.getURL().replacingOccurrences(of: "/v1", with: "")),
            let url = URL(string: last, relativeTo: baseURL)
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
        let url = "\(baseAPIurl)/exercises"
        return try await asyncRequestData(urlString: url)
    }
}
