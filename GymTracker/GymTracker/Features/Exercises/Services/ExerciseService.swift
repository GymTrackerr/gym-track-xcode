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

enum ExerciseCatalogSyncPhase: String {
    case idle
    case checking
    case downloading
    case applying
    case cachingThumbnails
    case completed
    case failed
}

struct ExerciseCatalogSyncState: Codable {
    var optedIn: Bool
    var hasSeenExistingUserPrompt: Bool
    var etag: String?
    var lastSuccessfulSyncAt: Date?
    var lastAttemptAt: Date?
}

final class ExerciseCatalogSyncStateStore {
    static let shared = ExerciseCatalogSyncStateStore()

    private let defaults: UserDefaults
    private let keyPrefix: String

    init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "gymtracker.exercise-catalog-sync."
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    func load(for userId: UUID) -> ExerciseCatalogSyncState? {
        guard let data = defaults.data(forKey: key(for: userId)) else { return nil }
        return try? JSONDecoder().decode(ExerciseCatalogSyncState.self, from: data)
    }

    func save(_ state: ExerciseCatalogSyncState, for userId: UUID) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key(for: userId))
    }

    private func key(for userId: UUID) -> String {
        "\(keyPrefix)\(userId.uuidString.lowercased())"
    }
}

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
    
    @Published private(set) var catalogSyncPhase: ExerciseCatalogSyncPhase = .idle
    @Published private(set) var catalogSyncProgressCompleted: Int = 0
    @Published private(set) var catalogSyncProgressTotal: Int = 0
    @Published private(set) var catalogSyncStatusText: String = ""
    @Published private(set) var catalogSyncEnabledForCurrentUser: Bool = false
    @Published private(set) var showExistingUserCatalogPrompt: Bool = false
    @Published private(set) var lastCatalogSyncError: String?
    @Published private(set) var lastCatalogRouteUsed: String?
    @Published private(set) var lastUserRouteUsed: String?

    var isCatalogSyncInFlight: Bool {
        switch catalogSyncPhase {
        case .checking, .downloading, .applying, .cachingThumbnails:
            return true
        case .idle, .completed, .failed:
            return false
        }
    }

    private let apiHelper: API_Helper
    private let repository: ExerciseRepositoryProtocol
    private let routeResolver: ExerciseRouteResolver
    private let catalogSyncStateStore: ExerciseCatalogSyncStateStore
    private let catalogSyncTTL: TimeInterval = 24 * 60 * 60
    private let thumbnailPrefetchConcurrency: Int = 3
    private var catalogSyncTask: Task<Void, Never>?

    init(
        context: ModelContext,
        repository: ExerciseRepositoryProtocol? = nil,
        apiHelper: API_Helper = API_Helper(),
        routeResolver: ExerciseRouteResolver = ExerciseRouteResolver(),
        catalogSyncStateStore: ExerciseCatalogSyncStateStore = .shared
    ) {
        self.apiHelper = apiHelper
        self.repository = repository ?? LocalExerciseRepository(modelContext: context)
        self.routeResolver = routeResolver
        self.catalogSyncStateStore = catalogSyncStateStore
        super.init(context: context)
    }

    override func loadFeature() {
        refreshExerciseLists()
        guard let user = currentUser else {
            catalogSyncTask?.cancel()
            catalogSyncTask = nil
            catalogSyncEnabledForCurrentUser = false
            showExistingUserCatalogPrompt = false
            catalogSyncPhase = .idle
            catalogSyncProgressCompleted = 0
            catalogSyncProgressTotal = 0
            catalogSyncStatusText = ""
            lastCatalogSyncError = nil
            lastCatalogRouteUsed = nil
            lastUserRouteUsed = nil
            return
        }

        guard user.isDemo != true else {
            catalogSyncTask?.cancel()
            catalogSyncTask = nil
            catalogSyncEnabledForCurrentUser = false
            showExistingUserCatalogPrompt = false
            lastCatalogRouteUsed = nil
            lastUserRouteUsed = nil
            return
        }

        let state = stateForUser(user.id)
        catalogSyncEnabledForCurrentUser = state.optedIn
        showExistingUserCatalogPrompt = !state.hasSeenExistingUserPrompt && !state.optedIn

        if state.optedIn {
            syncCatalogIfNeeded(reason: "userChanged")
        }
    }
    
    func loadExercises() {
        guard let userId = currentUser?.id else {
            exercises = []
            return
        }

        do {
            exercises = try repository.fetchActiveExercises(for: userId)
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
        await syncCatalogNow(force: true)
    }

    func refreshApiExercisesWithoutInsert() async {
        await syncCatalogNow(force: true)
    }

    func setCatalogSyncEnabled(_ enabled: Bool) {
        guard let userId = currentUser?.id else { return }
        var state = stateForUser(userId)
        state.optedIn = enabled
        state.hasSeenExistingUserPrompt = true
        saveState(state, for: userId)
        catalogSyncEnabledForCurrentUser = enabled
        showExistingUserCatalogPrompt = false

        if enabled {
            syncCatalogIfNeeded(reason: "toggleEnabled")
        }
    }

    func syncCatalogNow(force: Bool = true) async {
        if let existingTask = catalogSyncTask {
            await existingTask.value
            if !force {
                return
            }
        }
        let task = Task(priority: .utility) { @MainActor [weak self] in
            guard let self else { return }
            await self.runCatalogSync(force: force, reason: "manual")
        }
        catalogSyncTask = task
        await task.value
    }

    func acceptExistingUserCatalogPromptAndSync() {
        guard let userId = currentUser?.id else { return }
        var state = stateForUser(userId)
        state.optedIn = true
        state.hasSeenExistingUserPrompt = true
        saveState(state, for: userId)
        catalogSyncEnabledForCurrentUser = true
        showExistingUserCatalogPrompt = false
        Task(priority: .utility) { @MainActor in
            await self.syncCatalogNow(force: true)
        }
    }

    func dismissExistingUserCatalogPrompt() {
        guard let userId = currentUser?.id else { return }
        var state = stateForUser(userId)
        state.hasSeenExistingUserPrompt = true
        saveState(state, for: userId)
        showExistingUserCatalogPrompt = false
    }

    func completeOnboardingCatalogChoice(downloadCatalog: Bool) {
        guard let userId = currentUser?.id else { return }
        var state = stateForUser(userId)
        state.optedIn = downloadCatalog
        state.hasSeenExistingUserPrompt = true
        saveState(state, for: userId)
        catalogSyncEnabledForCurrentUser = downloadCatalog
        showExistingUserCatalogPrompt = false

        if downloadCatalog {
            Task(priority: .utility) { @MainActor in
                await self.syncCatalogNow(force: true)
            }
        }
    }

    private func syncCatalogIfNeeded(reason: String) {
        guard catalogSyncTask == nil else { return }
        catalogSyncTask = Task(priority: .utility) { @MainActor [weak self] in
            guard let self else { return }
            await self.runCatalogSync(force: false, reason: reason)
        }
    }

    private func runCatalogSync(force: Bool, reason: String) async {
        defer { catalogSyncTask = nil }

        guard let user = currentUser else { return }
        guard user.isDemo != true else { return }
        guard !Task.isCancelled else { return }

        var state = stateForUser(user.id)
        if !force && !state.optedIn {
            return
        }
        if !force, let lastSuccess = state.lastSuccessfulSyncAt {
            let age = Date().timeIntervalSince(lastSuccess)
            if age < catalogSyncTTL {
                return
            }
        }

        catalogSyncPhase = .checking
        catalogSyncProgressCompleted = 0
        catalogSyncProgressTotal = 1
        catalogSyncStatusText = "Checking ExerciseDB..."
        lastCatalogSyncError = nil

        let hasAuth = (BackendSessionStore.shared.accessToken?.isEmpty == false)
        let catalogSource = routeResolver.catalogSource(for: hasAuth)
        lastCatalogRouteUsed = catalogSource.routeDescription
        lastUserRouteUsed = nil
        var shouldPrefetchThumbnails = false

        do {
            let catalogResult = try await catalogSource.fetchCatalog(ifNoneMatch: state.etag)
            state.lastAttemptAt = Date()

            switch catalogResult {
            case .notModified(let etag):
                if let etag, !etag.isEmpty {
                    state.etag = etag
                }
                state.lastSuccessfulSyncAt = Date()

            case .catalog(let items, let etag):
                catalogSyncPhase = .downloading
                catalogSyncStatusText = "Downloading ExerciseDB..."
                catalogSyncProgressCompleted = 0
                catalogSyncProgressTotal = max(items.count, 1)

                catalogSyncPhase = .applying
                catalogSyncStatusText = "Applying ExerciseDB updates..."
                _ = try repository.applyCatalogExercises(items, for: user.id, allowInsert: true)
                refreshExerciseLists()
                catalogSyncProgressCompleted = catalogSyncProgressTotal
                shouldPrefetchThumbnails = true

                if let etag, !etag.isEmpty {
                    state.etag = etag
                }
                state.lastSuccessfulSyncAt = Date()
            }

            if let userSource = routeResolver.userSource(for: hasAuth) {
                lastUserRouteUsed = userSource.routeDescription
                let remoteUserRecords = try await userSource.fetchUserExercises()
                _ = try repository.applyRemoteUserExercises(remoteUserRecords, for: user.id)
                refreshExerciseLists()
            }

            if shouldPrefetchThumbnails {
                catalogSyncPhase = .cachingThumbnails
                catalogSyncStatusText = "Caching thumbnails..."
                let cacheCandidates = exercises
                    .filter { $0.isUserCreated == false }
                    .filter { !($0.images ?? []).isEmpty }
                catalogSyncProgressCompleted = 0
                catalogSyncProgressTotal = max(min(cacheCandidates.count, 300), 1)
                await prefetchThumbnails(for: cacheCandidates)
            }

            saveState(state, for: user.id)
            catalogSyncPhase = .completed
            catalogSyncStatusText = "ExerciseDB sync complete."
            _ = reason
        } catch {
            state.lastAttemptAt = Date()
            saveState(state, for: user.id)

            catalogSyncPhase = .failed
            catalogSyncStatusText = "ExerciseDB sync failed."
            lastCatalogSyncError = error.localizedDescription
        }
    }

    private func prefetchThumbnails(for exercisesToCache: [Exercise]) async {
        guard !exercisesToCache.isEmpty else {
            catalogSyncProgressCompleted = 1
            catalogSyncProgressTotal = 1
            return
        }

        let limitedCandidates = Array(exercisesToCache.prefix(300))
        for exercise in limitedCandidates {
            if Task.isCancelled { break }
            _ = await cacheThumbnail(for: exercise, forceRefresh: false)
            catalogSyncProgressCompleted += 1
            if catalogSyncProgressCompleted % max(thumbnailPrefetchConcurrency, 1) == 0 {
                await Task.yield()
            }
        }
        catalogSyncProgressCompleted = min(catalogSyncProgressCompleted, catalogSyncProgressTotal)
    }

    private func stateForUser(_ userId: UUID) -> ExerciseCatalogSyncState {
        catalogSyncStateStore.load(for: userId) ?? ExerciseCatalogSyncState(
            optedIn: false,
            hasSeenExistingUserPrompt: false,
            etag: nil,
            lastSuccessfulSyncAt: nil,
            lastAttemptAt: nil
        )
    }

    private func saveState(_ state: ExerciseCatalogSyncState, for userId: UUID) {
        catalogSyncStateStore.save(state, for: userId)
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
            return nil
        }
        return url
    }

    func gifURL(for exercise: Exercise) -> URL? {
        guard
            let last = exercise.images?.last,
            let url = apiHelper.resolveMediaURL(last)
        else {
            return nil
        }
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
        let result = try await asyncRequestRawData(route: APIRoute.exerciseDB)
        guard 200..<300 ~= result.response.statusCode else {
            let body = String(data: result.data, encoding: .utf8)
            throw APIHelperError.httpError(
                statusCode: result.response.statusCode,
                code: nil,
                message: "ExerciseDB request failed.",
                details: body
            )
        }
        return try ArrayOrEnvelopeDecoder.decode([ExerciseDTO].self, from: result.data)
    }
}
