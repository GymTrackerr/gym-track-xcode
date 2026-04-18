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
    var temporarilyHiddenNpIds: [String]

    init(
        optedIn: Bool,
        hasSeenExistingUserPrompt: Bool,
        etag: String?,
        lastSuccessfulSyncAt: Date?,
        lastAttemptAt: Date?,
        temporarilyHiddenNpIds: [String] = []
    ) {
        self.optedIn = optedIn
        self.hasSeenExistingUserPrompt = hasSeenExistingUserPrompt
        self.etag = etag
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.lastAttemptAt = lastAttemptAt
        self.temporarilyHiddenNpIds = temporarilyHiddenNpIds
    }

    private enum CodingKeys: String, CodingKey {
        case optedIn
        case hasSeenExistingUserPrompt
        case etag
        case lastSuccessfulSyncAt
        case lastAttemptAt
        case temporarilyHiddenNpIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        optedIn = try container.decode(Bool.self, forKey: .optedIn)
        hasSeenExistingUserPrompt = try container.decode(Bool.self, forKey: .hasSeenExistingUserPrompt)
        etag = try container.decodeIfPresent(String.self, forKey: .etag)
        lastSuccessfulSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulSyncAt)
        lastAttemptAt = try container.decodeIfPresent(Date.self, forKey: .lastAttemptAt)
        temporarilyHiddenNpIds =
            try container.decodeIfPresent([String].self, forKey: .temporarilyHiddenNpIds) ?? []
    }
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
    private struct CatalogOverlaySnapshot {
        let npId: String
        let aliases: [String]
        let isArchived: Bool
    }

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
    @Published private(set) var exerciseListRevision: Int = 0

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
    private let remoteRepository: RemoteExerciseRepository
    private let routeResolver: ExerciseRouteResolver
    private let catalogSyncStateStore: ExerciseCatalogSyncStateStore
    private let catalogSyncTTL: TimeInterval = 24 * 60 * 60
    private let thumbnailPrefetchConcurrency: Int = 3
    private var catalogSyncTask: Task<Void, Never>?
    private var catalogPreferenceTask: Task<Void, Never>?
    private var pendingRemoteCatalogPreference: Bool?

    init(
        context: ModelContext,
        repository: ExerciseRepositoryProtocol? = nil,
        apiHelper: API_Helper = API_Helper(),
        remoteRepository: RemoteExerciseRepository? = nil,
        routeResolver: ExerciseRouteResolver = ExerciseRouteResolver(),
        catalogSyncStateStore: ExerciseCatalogSyncStateStore = .shared
    ) {
        self.apiHelper = apiHelper
        self.repository = repository ?? LocalExerciseRepository(modelContext: context)
        self.remoteRepository = remoteRepository ?? RemoteExerciseRepository(apiHelper: apiHelper)
        self.routeResolver = routeResolver
        self.catalogSyncStateStore = catalogSyncStateStore
        super.init(context: context)
    }

    override func loadFeature() {
        refreshExerciseLists()
        resetExerciseSyncState()

        guard let user = currentUser, user.isDemo != true else {
            return
        }

        migrateCatalogPreferenceIfNeeded(for: user)
        scheduleExerciseSync(reason: "userChanged", forceCatalog: false)
    }

    override func sync() {
        scheduleExerciseSync(reason: "serviceSyncKickoff", forceCatalog: false)
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

    func setCatalogSyncEnabled(_ enabled: Bool) {
        guard let user = currentUser else { return }

        do {
            try applyCatalogPreferenceLocally(
                enabled,
                markPromptSeen: true,
                hideExercisesWhenDisabled: true
            )
        } catch {
            print("Failed to save catalog preference locally: \(error)")
        }

        catalogPreferenceTask?.cancel()
        pendingRemoteCatalogPreference = shouldPersistCatalogPreferenceRemotely(for: user) ? enabled : nil

        if enabled {
            catalogPreferenceTask = Task(priority: .utility) { @MainActor [weak self] in
                guard let self else { return }
                await self.persistCatalogPreferenceRemotelyIfNeeded(enabled)
                await self.syncCatalogNow(force: true)
            }
        } else {
            catalogSyncTask?.cancel()
            catalogSyncTask = nil
            resetCatalogSyncUI()
            catalogPreferenceTask = Task(priority: .utility) { @MainActor [weak self] in
                guard let self else { return }
                await self.persistCatalogPreferenceRemotelyIfNeeded(enabled)
            }
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
            await self.runExerciseSync(forceCatalog: force, reason: "manual")
        }
        catalogSyncTask = task
        await task.value
    }

    func acceptExistingUserCatalogPromptAndSync() {
        setCatalogSyncEnabled(true)
    }

    func dismissExistingUserCatalogPrompt() {
        guard let userId = currentUser?.id else { return }
        var state = stateForUser(userId)
        state.optedIn = currentUser?.exerciseCatalogEnabled ?? state.optedIn
        state.hasSeenExistingUserPrompt = true
        saveState(state, for: userId)
        showExistingUserCatalogPrompt = false
    }

    func completeOnboardingCatalogChoice(downloadCatalog: Bool) {
        setCatalogSyncEnabled(downloadCatalog)
    }

    private func scheduleExerciseSync(reason: String, forceCatalog: Bool) {
        guard catalogSyncTask == nil else { return }
        catalogSyncTask = Task(priority: .utility) { @MainActor [weak self] in
            guard let self else { return }
            await self.runExerciseSync(forceCatalog: forceCatalog, reason: reason)
        }
    }

    private func runExerciseSync(forceCatalog: Bool, reason: String) async {
        defer { catalogSyncTask = nil }
        guard let user = currentUser else { return }
        guard user.isDemo != true else { return }
        guard !Task.isCancelled else { return }

        await syncRemoteCatalogPreferenceIfNeeded(for: user)
        guard !Task.isCancelled else { return }

        await syncRemoteUserExercisesIfNeeded(for: user)
        guard !Task.isCancelled else { return }

        guard user.exerciseCatalogEnabled else { return }

        await runCatalogSync(force: forceCatalog, reason: reason)
    }

    private func runCatalogSync(force: Bool, reason: String) async {
        guard let user = currentUser else { return }
        guard user.isDemo != true else { return }
        guard user.exerciseCatalogEnabled else { return }
        guard !Task.isCancelled else { return }

        var state = stateForUser(user.id)
        let shouldFetchCatalog = shouldFetchCatalogBase(force: force, state: state)

        catalogSyncPhase = .checking
        catalogSyncProgressCompleted = 0
        catalogSyncProgressTotal = 1
        catalogSyncStatusText = "Checking ExerciseDB..."
        lastCatalogSyncError = nil

        let hasAuth = hasAuthorizedBackendSession
        let catalogSource = routeResolver.catalogSource(for: hasAuth)
        lastCatalogRouteUsed = catalogSource.routeDescription
        var shouldPrefetchThumbnails = false
        var didChangeCatalog = false

        do {
            if shouldFetchCatalog {
                let requestETag = force ? nil : state.etag
                let catalogResult = try await catalogSource.fetchCatalog(ifNoneMatch: requestETag)
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
                    let result = try repository.applyCatalogExercises(items, for: user.id, allowInsert: true)
                    didChangeCatalog = (result.inserted + result.updated + result.removed) > 0
                    catalogSyncProgressCompleted = catalogSyncProgressTotal
                    shouldPrefetchThumbnails = didChangeCatalog

                    if let etag, !etag.isEmpty {
                        state.etag = etag
                    }
                    state.lastSuccessfulSyncAt = Date()
                }
            }

            if let overlaySource = routeResolver.overlaySource(for: hasAuth) {
                let overlays = try await overlaySource.fetchCatalogOverlays(updatedAfter: nil)
                let overlayUpdates = try repository.applyCatalogOverlays(overlays, for: user.id)
                didChangeCatalog = didChangeCatalog || overlayUpdates > 0
            }

            if didChangeCatalog {
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

    private func resetCatalogSyncUI() {
        catalogSyncPhase = .idle
        catalogSyncProgressCompleted = 0
        catalogSyncProgressTotal = 0
        catalogSyncStatusText = ""
        lastCatalogSyncError = nil
    }

    private func resetExerciseSyncState() {
        catalogSyncTask?.cancel()
        catalogPreferenceTask?.cancel()
        catalogSyncTask = nil
        catalogPreferenceTask = nil
        pendingRemoteCatalogPreference = nil
        catalogSyncEnabledForCurrentUser = false
        showExistingUserCatalogPrompt = false
        resetCatalogSyncUI()
        lastCatalogRouteUsed = nil
        lastUserRouteUsed = nil
    }

    private func migrateCatalogPreferenceIfNeeded(for user: User) {
        var state = stateForUser(user.id)
        let resolvedEnabled = user.exerciseCatalogEnabled || state.optedIn

        if user.exerciseCatalogEnabled != resolvedEnabled {
            user.exerciseCatalogEnabled = resolvedEnabled
            user.updatedAt = Date()
            try? modelContext.save()
        }

        if state.optedIn != resolvedEnabled {
            state.optedIn = resolvedEnabled
            saveState(state, for: user.id)
        }

        catalogSyncEnabledForCurrentUser = resolvedEnabled
        showExistingUserCatalogPrompt = !state.hasSeenExistingUserPrompt && !resolvedEnabled
    }

    private func applyCatalogPreferenceLocally(
        _ enabled: Bool,
        markPromptSeen: Bool? = nil,
        hideExercisesWhenDisabled: Bool = false
    ) throws {
        guard let user = currentUser else { return }

        var shouldSaveUser = false
        if user.exerciseCatalogEnabled != enabled {
            user.exerciseCatalogEnabled = enabled
            user.updatedAt = Date()
            shouldSaveUser = true
        }

        var state = stateForUser(user.id)
        if state.optedIn != enabled {
            state.optedIn = enabled
        }
        if let markPromptSeen {
            state.hasSeenExistingUserPrompt = markPromptSeen
        }

        if shouldSaveUser {
            try modelContext.save()
        }

        if hideExercisesWhenDisabled && enabled == false {
            let result = try repository.hideCatalogExercises(for: user.id)
            state.temporarilyHiddenNpIds = result.hiddenNpIds
        } else if enabled, !state.temporarilyHiddenNpIds.isEmpty {
            _ = try repository.restoreCatalogExercises(
                withNpIds: state.temporarilyHiddenNpIds,
                for: user.id
            )
            state.temporarilyHiddenNpIds = []
        }

        saveState(state, for: user.id)

        catalogSyncEnabledForCurrentUser = enabled
        showExistingUserCatalogPrompt = !state.hasSeenExistingUserPrompt && !enabled
        if enabled == false {
            resetCatalogSyncUI()
        }
        refreshExerciseLists()
    }

    private var hasAuthorizedBackendSession: Bool {
        guard let accessToken = BackendSessionStore.shared.accessToken else {
            return false
        }
        return accessToken.isEmpty == false
    }

    private func shouldFetchCatalogBase(force: Bool, state: ExerciseCatalogSyncState) -> Bool {
        if force {
            return true
        }

        guard let lastSuccess = state.lastSuccessfulSyncAt else {
            return true
        }

        let age = Date().timeIntervalSince(lastSuccess)
        return age >= catalogSyncTTL
    }

    private func shouldPersistCatalogPreferenceRemotely(for user: User) -> Bool {
        user.remoteSyncEnabled && hasAuthorizedBackendSession
    }

    private func shouldAdoptRemoteCatalogPreference(
        _ remotePreference: Bool,
        for user: User
    ) -> Bool {
        let state = stateForUser(user.id)
        if state.hasSeenExistingUserPrompt {
            return false
        }
        if state.optedIn {
            return false
        }
        if user.exerciseCatalogEnabled {
            return false
        }
        return remotePreference
    }

    @MainActor
    private func reconcileRemoteCatalogPreference(
        _ remotePreference: Bool,
        for user: User
    ) async {
        if let pendingPreference = pendingRemoteCatalogPreference {
            if remotePreference == pendingPreference {
                pendingRemoteCatalogPreference = nil
            } else {
                await persistCatalogPreferenceRemotelyIfNeeded(pendingPreference)
            }
            return
        }

        if shouldAdoptRemoteCatalogPreference(remotePreference, for: user) {
            do {
                try applyCatalogPreferenceLocally(
                    remotePreference,
                    markPromptSeen: true,
                    hideExercisesWhenDisabled: true
                )
            } catch {
                print("Failed to adopt remote exercise catalog preference locally: \(error)")
            }
            return
        }

        guard user.exerciseCatalogEnabled != remotePreference else { return }
        await persistCatalogPreferenceRemotelyIfNeeded(user.exerciseCatalogEnabled)
    }

    @MainActor
    private func syncRemoteCatalogPreferenceIfNeeded(for user: User) async {
        guard user.remoteSyncEnabled else { return }
        guard hasAuthorizedBackendSession else { return }

        do {
            let response: BackendMeResponseDTO =
                try await apiHelper.asyncAuthorizedRequestData(route: APIRoute.me)

            var shouldSaveUser = false
            if user.remoteAccountId != response.id {
                user.remoteAccountId = response.id
                user.updatedAt = Date()
                shouldSaveUser = true
            }

            if let remotePreference = response.exerciseCatalogEnabled {
                await reconcileRemoteCatalogPreference(remotePreference, for: user)
            }

            if shouldSaveUser {
                try modelContext.save()
            }
        } catch {
            print("Failed to refresh remote exercise catalog preference: \(error)")
        }
    }

    @MainActor
    private func syncRemoteUserExercisesIfNeeded(for user: User) async {
        guard user.remoteSyncEnabled else {
            lastUserRouteUsed = nil
            return
        }
        guard hasAuthorizedBackendSession else {
            lastUserRouteUsed = nil
            return
        }
        guard let userSource = routeResolver.userSource(for: true) else {
            lastUserRouteUsed = nil
            return
        }

        do {
            lastUserRouteUsed = userSource.routeDescription
            let remoteExercises = try await userSource.fetchUserExercises()
            let result = try repository.applyRemoteUserExercises(remoteExercises, for: user.id)
            if (result.inserted + result.updated + result.removed) > 0 {
                refreshExerciseLists()
            }
        } catch {
            print("Failed to sync remote user exercises: \(error)")
        }
    }

    @MainActor
    private func persistCatalogPreferenceRemotelyIfNeeded(_ enabled: Bool) async {
        guard let user = currentUser else { return }
        guard shouldPersistCatalogPreferenceRemotely(for: user) else {
            pendingRemoteCatalogPreference = nil
            return
        }

        do {
            let response: BackendMeResponseDTO =
                try await apiHelper.asyncAuthorizedRequestData(
                    route: APIRoute.mePreferences,
                    httpMethod: .PATCH,
                    body: BackendMePreferencesUpdateRequest(exerciseCatalogEnabled: enabled)
                )

            var shouldSaveUser = false
            if user.remoteAccountId != response.id {
                user.remoteAccountId = response.id
                user.updatedAt = Date()
                shouldSaveUser = true
            }

            if let confirmedPreference = response.exerciseCatalogEnabled {
                if confirmedPreference == enabled {
                    pendingRemoteCatalogPreference = nil
                } else {
                    print("Remote exercise catalog preference did not match local pending value.")
                }
            } else {
                pendingRemoteCatalogPreference = nil
            }

            if shouldSaveUser {
                try modelContext.save()
            }
        } catch {
            print("Failed to push remote exercise catalog preference: \(error)")
        }
    }

    private func catalogOverlaySnapshot(for exercise: Exercise) -> CatalogOverlaySnapshot? {
        guard exercise.isUserCreated == false else { return nil }
        guard let npId = exercise.npId?.trimmingCharacters(in: .whitespacesAndNewlines), !npId.isEmpty else {
            return nil
        }

        return CatalogOverlaySnapshot(
            npId: npId,
            aliases: exercise.aliases ?? [],
            isArchived: exercise.isArchived || exercise.soft_deleted
        )
    }

    private func syncCatalogOverlayIfNeeded(snapshot: CatalogOverlaySnapshot?) {
        guard let snapshot else { return }
        guard let user = currentUser, user.remoteSyncEnabled else { return }
        guard hasAuthorizedBackendSession else { return }

        Task(priority: .utility) { [remoteRepository] in
            do {
                _ = try await remoteRepository.updateCatalogOverlay(
                    npId: snapshot.npId,
                    aliases: snapshot.aliases,
                    isArchived: snapshot.isArchived
                )
            } catch {
                print("Failed to push catalog overlay update: \(error)")
            }
        }
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
            let overlaySnapshot = catalogOverlaySnapshot(for: exercise)
            refreshExerciseLists()
            syncCatalogOverlayIfNeeded(snapshot: overlaySnapshot)
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
            let overlaySnapshot = catalogOverlaySnapshot(for: exercise)
            refreshExerciseLists()
            syncCatalogOverlayIfNeeded(snapshot: overlaySnapshot)
        } catch {
            print("Failed to restore exercise: \(error)")
        }
    }

    func delete(_ exercise: Exercise) throws {
        try repository.delete(exercise)
        syncCatalogOverlayIfNeeded(snapshot: catalogOverlaySnapshot(for: exercise))
    }

    func willArchiveOnDelete(_ exercise: Exercise) -> Bool {
        repository.willArchiveOnDelete(exercise)
    }

    func restore(_ exercise: Exercise) throws {
        try repository.restore(exercise)
        let overlaySnapshot = catalogOverlaySnapshot(for: exercise)
        refreshExerciseLists()
        syncCatalogOverlayIfNeeded(snapshot: overlaySnapshot)
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
        exerciseListRevision &+= 1
    }
}


extension ExerciseService {
    func thumbnailURL(images: [String], isUserCreated: Bool) -> URL? {
        guard
            let first = images.first,
            let url = apiHelper.resolveMediaURL(
                first,
                baseURLKind: isUserCreated ? .backend : .exerciseDB
            )
        else {
            return nil
        }
        return url
    }

    func thumbnailURL(for exercise: Exercise) -> URL? {
        thumbnailURL(images: exercise.images ?? [], isUserCreated: exercise.isUserCreated)
    }

    func gifURL(images: [String], isUserCreated: Bool) -> URL? {
        guard
            let last = images.last,
            let url = apiHelper.resolveMediaURL(
                last,
                baseURLKind: isUserCreated ? .backend : .exerciseDB
            )
        else {
            return nil
        }
        return url
    }

    func gifURL(for exercise: Exercise) -> URL? {
        gifURL(images: exercise.images ?? [], isUserCreated: exercise.isUserCreated)
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
