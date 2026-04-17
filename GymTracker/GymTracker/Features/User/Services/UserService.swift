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
    @Published var onBoarding: Bool = false
    @Published var onBoardingScreen: Int = 0
    @Published var currentUserLoggedin: UUID
    private let repository: UserRepositoryProtocol
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
                if (user==nil) {self.onBoarding=true}
                else if (self.accountCreated==false) {accountCreated = true}
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
                ensureDeviceIdForCurrentUser()
                accountCreated = true
                if (firstLoad==false) {
                    onBoarding = false
                }
            } else {
                currentUser = nil
                accountCreated = false
                onBoarding = true
            }
            
        } catch {
            accounts = []
            currentUser = nil
            accountCreated = false
            onBoarding = true

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
    
     
    func addUser(text: String) {
        let trimmedName = text.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return  }
        
        
        withAnimation {
            do {
                let newItem = try repository.createUser(name: trimmedName, isDemo: false)
                currentUser = newItem
                ensureDeviceIdForCurrentUser()
                accountCreated = true
                loadAccounts(firstLoad: true)
            } catch {
                print("Failed to save new split day: \(error)")
            }
        }
    }

    private func ensureDeviceIdForCurrentUser() {
        guard let currentUser else { return }
        _ = LocalDeviceIdentityStore.shared.deviceId(for: currentUser.id)
        BackendSessionStore.shared.setActiveLocalUserId(currentUser.id)
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
