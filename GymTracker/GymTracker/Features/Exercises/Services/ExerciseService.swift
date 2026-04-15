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
    private let repository: ExerciseRepositoryProtocol
    private var isLoadingApiExercises = false
    private var apiSyncedUserId: UUID?

    init(
        context: ModelContext,
        repository: ExerciseRepositoryProtocol? = nil,
        apiHelper: API_Helper = API_Helper(),
        exerciseApi: ExerciseApi? = nil
    ) {
        self.apiHelper = apiHelper
        self.exerciseApi = exerciseApi ?? ExerciseApi(apiHelper: apiHelper)
        self.repository = repository ?? LocalExerciseRepository(modelContext: context)
        super.init(context: context)
    }

    override func loadFeature() {
        refreshExerciseLists()
        guard let userId = currentUser?.id else { return }
        guard currentUser?.isDemo != true else {
            apiSyncedUserId = nil
            return
        }
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

        do {
            exercises = try repository.fetchActiveExercises(for: userId)
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

        do {
            archivedExercises = try repository.fetchArchivedExercises(for: userId)
        } catch {
            archivedExercises = []
        }
    }

    func loadApiExercises() async {
        await loadApiExercises(allowInsert: true)
    }

    func refreshApiExercisesWithoutInsert() async {
        await loadApiExercises(allowInsert: false)
    }

    private func loadApiExercises(allowInsert: Bool) async {
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
                try self.applyApiExercises(data, userId: userId, allowInsert: allowInsert)
            }
            await MainActor.run {
                self.loadExercises()
                self.loadArchivedExercises()
                self.apiSyncedUserId = userId
            }

            // TODO, only cache on launch
            await cacheMediaForUserExercises(userId: userId)
            print("Cached all non-user exercise thumbnails and GIFs.")
            let modeLabel = allowInsert ? "full sync" : "update-only sync"
            print("Loaded \(data.count) exercises from API (\(result.inserted) new, \(result.updated) updated, \(result.removed) deduped) [\(modeLabel)]")
        } catch {
            print("Error loading API exercises: \(error)")
        }
    }

    @MainActor
    private func applyApiExercises(
        _ data: [ExerciseDTO],
        userId: UUID,
        allowInsert: Bool
    ) throws -> (inserted: Int, updated: Int, removed: Int) {
        try repository.applyCatalogExercises(data, for: userId, allowInsert: allowInsert)
    }

    @MainActor
    private func cacheMediaForUserExercises(userId: UUID) async {
        do {
            let cacheCandidates = try fetchExercisesForUser(userId: userId)
            for exercise in cacheCandidates {
                let imageCount = exercise.images?.count ?? 0
                if imageCount == 0 {
                    print("Skipping media cache: id=\(exercise.id), npId=\(exercise.npId ?? "nil"), no images present.")
                    exercise.cachedMedia = false
                    continue
                }

                let cacheStatusBefore = await hasCachedMedia(for: exercise)
                if exercise.cachedMedia == true && cacheStatusBefore.thumbnail && cacheStatusBefore.gif {
                    print("Skipping media cache: id=\(exercise.id), npId=\(exercise.npId ?? "nil"), already cached.")
                    continue
                }
                if exercise.cachedMedia == true && (!cacheStatusBefore.thumbnail || !cacheStatusBefore.gif) {
                    print("Media cache flag stale: id=\(exercise.id), npId=\(exercise.npId ?? "nil"), thumbnailCached=\(cacheStatusBefore.thumbnail), gifCached=\(cacheStatusBefore.gif). Re-caching.")
                }

                print("Caching exercise media: id=\(exercise.id), npId=\(exercise.npId ?? "nil"), imageCount=\(imageCount)")

                async let thumb = self.cacheThumbnail(for: exercise, forceRefresh: true)
                async let gif = self.cacheGIF(for: exercise, forceRefresh: true)
                _ = await (thumb, gif)

                let cacheStatusAfter = await hasCachedMedia(for: exercise)
                exercise.cachedMedia = cacheStatusAfter.thumbnail && cacheStatusAfter.gif
                try? repository.saveChanges()
                print("Finished caching exercise media: id=\(exercise.id), npId=\(exercise.npId ?? "nil"), thumbnailCached=\(cacheStatusAfter.thumbnail), gifCached=\(cacheStatusAfter.gif), cachedMedia=\(exercise.cachedMedia ?? false)")
            }
        } catch {
            print("Failed to load exercises for media caching: \(error)")
        }
    }

    @MainActor
    private func fetchExercisesForUser(userId: UUID) throws -> [Exercise] {
        try repository.fetchActiveExercises(for: userId)
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
        do {
            try repository.setAliases(aliases, for: exercise)
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
        
        var newItem: Exercise?
        var failed = false
        
        withAnimation {
            do {
                newItem = try repository.createExercise(name: trimmedName, type: selectedExerciseType, userId: userId)
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
        return newItem
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
        do {
            try repository.reinsertOrRestore(exercise)
            refreshExerciseLists()
        } catch {
            print("Failed to restore exercise: \(error)")
        }
    }

    func delete(_ exercise: Exercise) throws {
        try repository.delete(exercise)
    }

    func willArchiveOnDelete(_ exercise: Exercise) -> Bool {
        repository.willArchiveOnDelete(exercise)
    }

    func restore(_ exercise: Exercise) throws {
        try repository.restore(exercise)
        refreshExerciseLists()
    }

    @MainActor
    func mergeExercisesWithSameNpId() throws -> NpIdMergeReport {
        guard let currentUserId = currentUser?.id else {
            return NpIdMergeReport(groupsMerged: 0, duplicatesRemoved: 0)
        }
        let report = try repository.mergeExercisesWithSameNpId(for: currentUserId)

        refreshExerciseLists()
        return NpIdMergeReport(groupsMerged: report.groupsMerged, duplicatesRemoved: report.duplicatesRemoved)
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
    func cacheThumbnail(for exercise: Exercise, forceRefresh: Bool = false) async -> URL? {
        guard let url = self.thumbnailURL(for: exercise) else { return nil }
        do {
            return try await MediaCache.shared.fetch(url, forceRefresh: forceRefresh)
        } catch {
            print("⚠️ Failed to cache thumbnail for \(exercise.name): \(error)")
            return nil
        }
    }

    /// Caches the GIF (.last image)
    func cacheGIF(for exercise: Exercise, forceRefresh: Bool = false) async -> URL? {
        guard let url = self.gifURL(for: exercise) else { return nil }
        do {
            return try await MediaCache.shared.fetch(url, forceRefresh: forceRefresh)
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
