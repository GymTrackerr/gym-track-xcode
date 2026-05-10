//
//  UserService.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-03.
//

import SwiftUI
import SwiftData
import Combine
internal import CoreData

class UserService: ServiceBase, ObservableObject {
    @Published var accountCreated: Bool = false
    @Published var accounts: [User] = []
    @Published var onboardingState: OnboardingState?
    @Published private(set) var canDismissOnboarding: Bool = false
    @Published var currentUserLoggedin: UUID
    private let repository: UserRepositoryProtocol
    private var manualOnboardingOverride: OnboardingState?
    private var onboardingReturnUserId: UUID?
//    @Published override var currentUser: User?: User? = nil
    
    init(context: ModelContext, repository: UserRepositoryProtocol) {
        self.repository = repository
        self.currentUserLoggedin = UUID()

        super.init(context: context)
//        if (self.currentUser)
        // react to currentUser changing
        self.$currentUser
            .sink { [weak self] user in
                guard let self else { return }
                self.accountCreated = (user != nil)
                self.refreshOnboardingState(for: user)
                self.ensureDeviceIdForCurrentUser()
            }
            .store(in: &cancellables)
    }
    
    override func loadFeature() {
        self.loadAccounts()
    }
    
    @MainActor
    func loadAccountsIfNeeded() {
        guard currentUser == nil else { return }
        loadAccounts() // your existing function
    }

    func loadAccounts(firstLoad: Bool = false) {
        do {
            accounts = try repository.fetchAccounts()

            if let first = accounts.first {
                currentUser = first
            } else {
                currentUser = nil
            }
        } catch {
            accounts = []
            currentUser = nil
        }
    }

    func switchAccount(to userId: UUID) {
        guard let account = accounts.first(where: { $0.id == userId }) else { return }

        withAnimation {
            account.lastLogin = Date()
            account.updatedAt = account.lastLogin
            currentUser = account
            ensureDeviceIdForCurrentUser()

            do {
                try repository.saveChanges(for: account)
                loadAccounts()
            } catch {
                print("Failed to switch account: \(error)")
            }
        }
    }
    
    func removeUser(id: UUID) {
        withAnimation {
            LocalDeviceIdentityStore.shared.clearDeviceId(for: id)
            BackendSessionStore.shared.clearSession(for: id)
            if let account = accounts.first(where: { $0.id == id }) {
                do {
                    try repository.delete(account)
                    loadAccounts()
                } catch {
                    print("Failed to save new split day: \(error)")
                }
            }
        }
    }
    
     
    @discardableResult
    func addUser(text: String) -> User? {
        let trimmedName = text.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return nil }

        var createdUser: User?
        withAnimation {
            do {
                let newItem = try repository.createUser(name: trimmedName, isDemo: false)
                manualOnboardingOverride = nil
                currentUser = newItem
                loadAccounts(firstLoad: true)
                createdUser = newItem
            } catch {
                print("Failed to save new split day: \(error)")
            }
        }

        return createdUser
    }

    func renameCurrentUser(to name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard let currentUser else { return }
        guard currentUser.name != trimmedName else { return }

        withAnimation {
            currentUser.name = trimmedName
            currentUser.updatedAt = Date()
            try? repository.saveChanges(for: currentUser)
        }
    }

    func setCurrentOnboardingGoals(_ goals: Set<OnboardingGoal>) {
        guard let currentUser else { return }
        guard currentUser.onboardingGoals != goals else { return }

        withAnimation {
            currentUser.onboardingGoals = goals
            currentUser.updatedAt = Date()
            try? repository.saveChanges(for: currentUser)
        }
    }

    func setCurrentTrainingExperience(_ experience: OnboardingExperienceLevel?) {
        guard let currentUser else { return }
        guard currentUser.trainingExperience != experience else { return }

        withAnimation {
            currentUser.trainingExperience = experience
            currentUser.updatedAt = Date()
            try? repository.saveChanges(for: currentUser)
        }
    }

    func completeOnboarding() {
        guard let currentUser else { return }

        withAnimation {
            currentUser.onboardingStatus = .completed
            currentUser.updatedAt = Date()
            manualOnboardingOverride = nil
            onboardingReturnUserId = nil
            canDismissOnboarding = false

            do {
                try repository.saveChanges(for: currentUser)
                onboardingState = nil
            } catch {
                print("Failed to complete onboarding: \(error)")
            }
        }
    }

    func restartOnboarding() {
        let onboardingUserId = currentUser?.needsOnboarding == true ? currentUser?.id : nil
        let returnAccountId = preferredReturnAccountId(excluding: onboardingUserId)

        if let onboardingUserId {
            do {
                try purgeOnboardingArtifacts(for: onboardingUserId)
            } catch {
                print("Failed to purge onboarding artifacts: \(error)")
            }

            removeUser(id: onboardingUserId)
        }

        if let returnAccountId, currentUser?.id != returnAccountId {
            switchAccount(to: returnAccountId)
        }

        startNewAccountOnboarding()
    }

    private func ensureDeviceIdForCurrentUser() {
        guard let currentUser else { return }
        _ = LocalDeviceIdentityStore.shared.deviceId(for: currentUser.id)
        BackendSessionStore.shared.setActiveLocalUserId(currentUser.id)
    }

    private func preferredReturnAccountId(excluding removedUserId: UUID?) -> UUID? {
        let remainingAccounts = accounts.filter { account in
            account.soft_deleted == false && account.id != removedUserId
        }

        if let completedAccount = remainingAccounts.first(where: { !$0.needsOnboarding }) {
            return completedAccount.id
        }

        return remainingAccounts.first?.id
    }

    private func purgeOnboardingArtifacts(for userId: UUID) throws {
        let reps = try modelContext.fetch(FetchDescriptor<SessionRep>()).filter { $0.sessionSet.sessionEntry.session.user_id == userId }
        for rep in reps { modelContext.delete(rep) }

        let sets = try modelContext.fetch(FetchDescriptor<SessionSet>()).filter { $0.sessionEntry.session.user_id == userId }
        for sessionSet in sets { modelContext.delete(sessionSet) }

        let entries = try modelContext.fetch(FetchDescriptor<SessionEntry>()).filter { $0.session.user_id == userId }
        for entry in entries { modelContext.delete(entry) }

        let sessions = try modelContext.fetch(FetchDescriptor<Session>()).filter { $0.user_id == userId }
        for session in sessions { modelContext.delete(session) }

        let splitDays = try modelContext.fetch(FetchDescriptor<ExerciseSplitDay>()).filter { $0.routine.user_id == userId }
        for splitDay in splitDays { modelContext.delete(splitDay) }

        let progressionExercises = try modelContext.fetch(FetchDescriptor<ProgressionExercise>()).filter { $0.user_id == userId }
        for progressionExercise in progressionExercises { modelContext.delete(progressionExercise) }

        let programs = try modelContext.fetch(FetchDescriptor<Program>()).filter { $0.user_id == userId }
        for program in programs { modelContext.delete(program) }

        let routines = try modelContext.fetch(FetchDescriptor<Routine>()).filter { $0.user_id == userId }
        for routine in routines { modelContext.delete(routine) }

        let exercises = try modelContext.fetch(FetchDescriptor<Exercise>()).filter { $0.user_id == userId }
        for exercise in exercises { modelContext.delete(exercise) }

        let progressionProfiles = try modelContext.fetch(FetchDescriptor<ProgressionProfile>()).filter { $0.user_id == userId }
        for profile in progressionProfiles { modelContext.delete(profile) }

        try modelContext.save()
    }

    private func makeOnboardingState(for user: User?) -> OnboardingState? {
        guard let user else { return .noAccount }
        guard user.needsOnboarding else { return nil }
        return .required(userId: user.id)
    }

    func startNewAccountOnboarding() {
        onboardingReturnUserId = currentUser?.id
        manualOnboardingOverride = .noAccount
        refreshOnboardingState(for: currentUser)
    }

    func cancelNewAccountOnboarding() {
        let returnUserId = onboardingReturnUserId
        manualOnboardingOverride = nil
        onboardingReturnUserId = nil
        canDismissOnboarding = false

        if let returnUserId, currentUser?.id != returnUserId {
            switchAccount(to: returnUserId)
            return
        }

        refreshOnboardingState(for: currentUser)
    }

    private func refreshOnboardingState(for user: User?) {
        onboardingState = manualOnboardingOverride ?? makeOnboardingState(for: user)
        canDismissOnboarding = onboardingReturnUserId != nil
    }
    
    func hkUserAllow(connected: Bool, requested: Bool) {
        withAnimation {
            currentUser?.allowHealthAccess = connected && requested
            currentUser?.updatedAt = Date()
            if let currentUser { try? repository.saveChanges(for: currentUser) }
        }
    }

    func setShowNutritionTab(_ isVisible: Bool) {
        withAnimation {
            currentUser?.showNutritionTab = isVisible
            currentUser?.updatedAt = Date()
            if let currentUser { try? repository.saveChanges(for: currentUser) }
        }
    }

    func setRemoteSyncEnabled(_ isEnabled: Bool) {
        withAnimation {
            currentUser?.remoteSyncEnabled = isEnabled
            currentUser?.updatedAt = Date()
            if let currentUser { try? repository.saveChanges(for: currentUser) }
        }
    }

    func currentHealthHistorySyncRange() -> HealthHistorySyncRange {
        guard let raw = currentUser?.preferredHealthHistorySyncRangeRaw else {
            return .defaultSelection
        }
        return HealthHistorySyncRange(rawValue: raw) ?? .defaultSelection
    }

    func setCurrentHealthHistorySyncRange(_ range: HealthHistorySyncRange) {
        withAnimation {
            currentUser?.preferredHealthHistorySyncRangeRaw = range.rawValue
            currentUser?.updatedAt = Date()
            if let currentUser { try? repository.saveChanges(for: currentUser) }
        }
    }

    var currentAppearancePreference: AppAppearancePreference {
        currentUser?.preferredAppearance ?? .system
    }

    func setCurrentAppearancePreference(_ preference: AppAppearancePreference) {
        withAnimation {
            currentUser?.preferredAppearance = preference
            currentUser?.updatedAt = Date()
            if let currentUser { try? repository.saveChanges(for: currentUser) }
        }
    }

    func setTimerNotificationsEnabled(_ isEnabled: Bool) {
        withAnimation {
            currentUser?.timerNotificationsEnabled = isEnabled
            currentUser?.updatedAt = Date()
            if let currentUser { try? repository.saveChanges(for: currentUser) }
        }
    }

    func setTimerFinishedNotificationEnabled(_ isEnabled: Bool) {
        withAnimation {
            currentUser?.timerFinishedNotificationEnabled = isEnabled
            currentUser?.updatedAt = Date()
            if let currentUser { try? repository.saveChanges(for: currentUser) }
        }
    }

    func setAwayTooLongEnabled(_ isEnabled: Bool) {
        withAnimation {
            currentUser?.awayTooLongEnabled = isEnabled
            currentUser?.updatedAt = Date()
            if let currentUser { try? repository.saveChanges(for: currentUser) }
        }
    }

    func setAwayTooLongMinutes(_ minutes: Int) {
        withAnimation {
            currentUser?.awayTooLongMinutes = max(1, minutes)
            currentUser?.updatedAt = Date()
            if let currentUser { try? repository.saveChanges(for: currentUser) }
        }
    }

    func setCountdownHapticsEnabled(_ isEnabled: Bool) {
        withAnimation {
            currentUser?.countdownHapticsEnabled = isEnabled
            currentUser?.updatedAt = Date()
            if let currentUser { try? repository.saveChanges(for: currentUser) }
        }
    }

    func setHapticAt30(_ isEnabled: Bool) {
        withAnimation {
            currentUser?.hapticAt30 = isEnabled
            currentUser?.updatedAt = Date()
            if let currentUser { try? repository.saveChanges(for: currentUser) }
        }
    }

    func setHapticAt15(_ isEnabled: Bool) {
        withAnimation {
            currentUser?.hapticAt15 = isEnabled
            currentUser?.updatedAt = Date()
            if let currentUser { try? repository.saveChanges(for: currentUser) }
        }
    }

    func setHapticAt5(_ isEnabled: Bool) {
        withAnimation {
            currentUser?.hapticAt5 = isEnabled
            currentUser?.updatedAt = Date()
            if let currentUser { try? repository.saveChanges(for: currentUser) }
        }
    }
}
