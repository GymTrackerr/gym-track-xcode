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
//    @Published override var currentUser: User?: User? = nil
    
    override init (context: ModelContext) {
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
        print("loadingaccounts")
        let descriptor = FetchDescriptor<User>(sortBy: [SortDescriptor(\.lastLogin, order: .reverse)])

        do {
            print("not ??")

            accounts = try modelContext.fetch(descriptor)
            
            print("ac", accounts.count)
            for item in accounts {
                print("id: \(item.id), name: \(item.name), timestamp: \(item.timestamp)")
            }

            if let first = accounts.first {
                currentUser = first
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
            print("not create")
            accounts = []
            currentUser = nil
            accountCreated = false
            onBoarding = true

        }
        print("??")
    }

    func switchAccount(to userId: UUID) {
        guard let account = accounts.first(where: { $0.id == userId }) else { return }

        withAnimation {
            account.lastLogin = Date()
            currentUser = account

            do {
                try modelContext.save()
                loadAccounts()
            } catch {
                print("Failed to switch account: \(error)")
            }
        }
    }
    
    func removeUser(id: UUID) {
        withAnimation {
            modelContext.delete(accounts.first(where: { $0.id == id })!)
            
            do {
                try modelContext.save()
                loadAccounts()
            } catch {
                print("Failed to save new split day: \(error)")
            }
        }
    }
    
     
    func addUser(text: String) {
        print("ccreating \(text)")
        let trimmedName = text.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return  }
        
        
        withAnimation {
//            modelContext.
            let newItem = User(name:trimmedName)

            
            modelContext.insert(newItem)
            
            do {
                try modelContext.save()
                currentUser = newItem
                accountCreated = true
                loadAccounts(firstLoad: true)
            } catch {
                print("Failed to save new split day: \(error)")
            }
        }
    }
    
    func hkUserAllow(connected: Bool, requested: Bool) {
        withAnimation {
            currentUser?.allowHealthAccess = connected && requested
            try? modelContext.save()
        }
    }

    func setShowNutritionTab(_ isVisible: Bool) {
        withAnimation {
            currentUser?.showNutritionTab = isVisible
            try? modelContext.save()
        }
    }

    func setTimerNotificationsEnabled(_ isEnabled: Bool) {
        withAnimation {
            currentUser?.timerNotificationsEnabled = isEnabled
            try? modelContext.save()
        }
    }

    func setTimerFinishedNotificationEnabled(_ isEnabled: Bool) {
        withAnimation {
            currentUser?.timerFinishedNotificationEnabled = isEnabled
            try? modelContext.save()
        }
    }

    func setAwayTooLongEnabled(_ isEnabled: Bool) {
        withAnimation {
            currentUser?.awayTooLongEnabled = isEnabled
            try? modelContext.save()
        }
    }

    func setAwayTooLongMinutes(_ minutes: Int) {
        withAnimation {
            currentUser?.awayTooLongMinutes = max(1, minutes)
            try? modelContext.save()
        }
    }

    func setCountdownHapticsEnabled(_ isEnabled: Bool) {
        withAnimation {
            currentUser?.countdownHapticsEnabled = isEnabled
            try? modelContext.save()
        }
    }

    func setHapticAt30(_ isEnabled: Bool) {
        withAnimation {
            currentUser?.hapticAt30 = isEnabled
            try? modelContext.save()
        }
    }

    func setHapticAt15(_ isEnabled: Bool) {
        withAnimation {
            currentUser?.hapticAt15 = isEnabled
            try? modelContext.save()
        }
    }

    func setHapticAt5(_ isEnabled: Bool) {
        withAnimation {
            currentUser?.hapticAt5 = isEnabled
            try? modelContext.save()
        }
    }
}
