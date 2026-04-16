//
//  BackendAuthService.swift
//  GymTracker
//
//  Created by Codex on 2026-04-15.
//

import Foundation
import Combine
import Network

final class SyncEligibilityState: ObservableObject {
    @Published var backendEnabled: Bool
    @Published var networkAvailable: Bool
    @Published var authAvailable: Bool
    @Published var hasActiveLocalUser: Bool

    init(
        backendEnabled: Bool = false,
        networkAvailable: Bool = true,
        authAvailable: Bool = false,
        hasActiveLocalUser: Bool = false
    ) {
        self.backendEnabled = backendEnabled
        self.networkAvailable = networkAvailable
        self.authAvailable = authAvailable
        self.hasActiveLocalUser = hasActiveLocalUser
    }

    var isSyncEligible: Bool {
        backendEnabled && networkAvailable && authAvailable && hasActiveLocalUser
    }
}

final class BackendAuthService: ObservableObject {
    @Published private(set) var sessionSnapshot: BackendSessionSnapshot?
    @Published private(set) var currentSession: BackendCurrentSessionResponseDTO?
    @Published private(set) var currentBackendUser: BackendMeResponseDTO?
    @Published private(set) var linkedProvider: BackendLinkedProviderDTO?
    @Published private(set) var lastErrorMessage: String?

    let apiHelper: API_Helper
    let eligibilityState: SyncEligibilityState
    private let eligibilityStateStore: SyncEligibilityStateStore
    private let bootstrapCoordinator: AccountBootstrapCoordinating?

    private var cancellables = Set<AnyCancellable>()
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "gymtracker.backend-auth.network-monitor")
    private let iso8601Formatter: ISO8601DateFormatter
    private var currentLocalUserId: UUID?

    init(
        apiHelper: API_Helper = API_Helper(),
        eligibilityState: SyncEligibilityState = SyncEligibilityState(),
        eligibilityStateStore: SyncEligibilityStateStore = .shared,
        bootstrapCoordinator: AccountBootstrapCoordinating? = nil
    ) {
        self.apiHelper = apiHelper
        self.eligibilityState = eligibilityState
        self.eligibilityStateStore = eligibilityStateStore
        self.bootstrapCoordinator = bootstrapCoordinator

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.iso8601Formatter = formatter

        startNetworkMonitor()
        restoreStoredSessionForActiveUser()
        bindEligibilityPersistence()
    }

    deinit {
        pathMonitor.cancel()
    }

    func bind(to userService: UserService) {
        userService.$currentUser
            .sink { [weak self] user in
                self?.handleCurrentUserChange(user)
            }
            .store(in: &cancellables)
    }

    @MainActor
    func loginInteract(username: String, password: String) async throws -> BackendAuthSessionResponseDTO {
        let response: BackendAuthSessionResponseDTO = try await apiHelper.asyncRequestData(
            route: APIRoute.authInteractLogin,
            httpMethod: .POST,
            body: InteractLoginRequest(username: username, password: password)
        )
        persistSession(from: response)
        return response
    }

    @MainActor
    func exchangeInteract(bundle: InteractBundlePayload) async throws -> BackendAuthSessionResponseDTO {
        let response: BackendAuthSessionResponseDTO = try await apiHelper.asyncRequestData(
            route: APIRoute.authInteractExchange,
            httpMethod: .POST,
            body: InteractExchangeRequest(bundle: bundle)
        )
        persistSession(from: response)
        return response
    }

    @MainActor
    func refreshCurrentSession() async throws -> BackendCurrentSessionResponseDTO {
        let response: BackendCurrentSessionResponseDTO =
            try await apiHelper.asyncAuthorizedRequestData(route: APIRoute.authSession)
        currentSession = response
        linkedProvider = response.linkedProvider
        eligibilityState.authAvailable = true
        triggerBootstrapIfEligible(accountUserId: response.user.id)
        return response
    }

    @MainActor
    func fetchCurrentUser() async throws -> BackendMeResponseDTO {
        let response: BackendMeResponseDTO =
            try await apiHelper.asyncAuthorizedRequestData(route: APIRoute.me)
        currentBackendUser = response
        return response
    }

    @MainActor
    func logoutCurrentSession() async throws {
        let response: BackendLogoutResponseDTO =
            try await apiHelper.asyncAuthorizedRequestData(route: APIRoute.authLogout, httpMethod: .POST)

        if response.ok {
            clearStoredSessionForCurrentUser()
        }
    }

    private func startNetworkMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.eligibilityState.networkAvailable = path.status == .satisfied
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    private func restoreStoredSessionForActiveUser() {
        if let activeLocalUserId = BackendSessionStore.shared.activeLocalUserId() {
            currentLocalUserId = activeLocalUserId
            sessionSnapshot = BackendSessionStore.shared.loadSession(for: activeLocalUserId)
            let persistedEligibility = eligibilityStateStore.load(for: activeLocalUserId)
            eligibilityState.hasActiveLocalUser = true
            eligibilityState.backendEnabled = persistedEligibility?.backendEnabled ?? true
            if let persistedEligibility {
                eligibilityState.networkAvailable = persistedEligibility.networkAvailable
            }
            eligibilityState.authAvailable = sessionSnapshot?.accessToken.isEmpty == false
            triggerBootstrapIfEligible(accountUserId: sessionSnapshot?.accountUserId)
        }
    }

    private func handleCurrentUserChange(_ user: User?) {
        currentLocalUserId = user?.id
        eligibilityState.hasActiveLocalUser = user != nil
        eligibilityState.backendEnabled = user?.remoteSyncEnabled ?? false
        BackendSessionStore.shared.setActiveLocalUserId(user?.id)

        guard let localUserId = user?.id else {
            sessionSnapshot = nil
            currentSession = nil
            currentBackendUser = nil
            linkedProvider = nil
            lastErrorMessage = nil
            eligibilityState.authAvailable = false
            return
        }

        sessionSnapshot = BackendSessionStore.shared.loadSession(for: localUserId)
        currentSession = nil
        currentBackendUser = nil
        linkedProvider = nil
        lastErrorMessage = nil

        if let accountUserId = sessionSnapshot?.accountUserId, user?.remoteAccountId == nil {
            user?.remoteAccountId = accountUserId
            user?.updatedAt = Date()
        }

        eligibilityState.authAvailable = sessionSnapshot?.accessToken.isEmpty == false
        triggerBootstrapIfEligible(accountUserId: sessionSnapshot?.accountUserId)
    }

    @MainActor
    private func persistSession(from response: BackendAuthSessionResponseDTO) {
        guard let localUserId = currentLocalUserId else {
            lastErrorMessage = "Cannot persist backend session without an active local user."
            return
        }

        let snapshot = BackendSessionSnapshot(
            accessToken: response.session.accessToken,
            expiresAt: parseDate(response.session.expiresAt),
            accountUserId: response.user.id
        )

        BackendSessionStore.shared.saveSession(snapshot, for: localUserId)
        sessionSnapshot = snapshot
        currentBackendUser = BackendMeResponseDTO(
            id: response.user.id,
            displayName: response.user.displayName,
            username: response.user.username
        )
        linkedProvider = response.linkedProvider
        currentSession = nil
        lastErrorMessage = nil
        eligibilityState.backendEnabled = true
        eligibilityState.authAvailable = true
        triggerBootstrapIfEligible(accountUserId: response.user.id)
    }

    @MainActor
    private func clearStoredSessionForCurrentUser() {
        if let localUserId = currentLocalUserId {
            BackendSessionStore.shared.clearSession(for: localUserId)
        }

        sessionSnapshot = nil
        currentSession = nil
        currentBackendUser = nil
        linkedProvider = nil
        lastErrorMessage = nil
        eligibilityState.authAvailable = false
    }

    private func bindEligibilityPersistence() {
        Publishers.CombineLatest4(
            eligibilityState.$backendEnabled,
            eligibilityState.$networkAvailable,
            eligibilityState.$authAvailable,
            eligibilityState.$hasActiveLocalUser
        )
        .sink { [weak self] backendEnabled, networkAvailable, authAvailable, hasActiveLocalUser in
            guard
                let self,
                let localUserId = self.currentLocalUserId
            else { return }

            let snapshot = PersistedSyncEligibilitySnapshot(
                backendEnabled: backendEnabled,
                networkAvailable: networkAvailable,
                authAvailable: authAvailable,
                hasActiveLocalUser: hasActiveLocalUser,
                updatedAt: Date()
            )
            self.eligibilityStateStore.save(snapshot, for: localUserId)
        }
        .store(in: &cancellables)
    }

    private func triggerBootstrapIfEligible(accountUserId: String?) {
        guard
            let bootstrapCoordinator,
            let localUserId = currentLocalUserId,
            let accountUserId,
            accountUserId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else { return }

        let syncEnabled =
            eligibilityState.backendEnabled &&
            eligibilityState.networkAvailable &&
            eligibilityState.authAvailable &&
            eligibilityState.hasActiveLocalUser
        bootstrapCoordinator.triggerBootstrapIfNeeded(
            localUserId: localUserId,
            accountUserId: accountUserId,
            syncEnabled: syncEnabled
        )
    }

    private func parseDate(_ value: String) -> Date? {
        if let parsed = iso8601Formatter.date(from: value) {
            return parsed
        }

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        return fallbackFormatter.date(from: value)
    }
}
