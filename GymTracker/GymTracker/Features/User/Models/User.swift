//
//  User.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-03.
//

import Foundation
import SwiftData

@Model
final class User {
    var id: UUID = UUID()
    var name: String
    var timestamp: Date
    var lastLogin: Date
    var soft_deleted: Bool = false
    var syncMetaId: UUID? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var active: Bool = true
    var isDemo: Bool = false
    var allowHealthAccess: Bool = false
    var remoteAccountId: String? = nil
    var remoteSyncEnabled: Bool = true
    var exerciseCatalogEnabled: Bool = false
    var onboardingStatusRaw: String? = nil
    var onboardingGoalsRaw: [String] = []
    var trainingExperienceRaw: String? = nil
    var globalProgressionEnabledStored: Bool? = nil
    var defaultProgressionProfileId: UUID? = nil
    
    var defaultTimer: Int = 90
    var showNutritionTab: Bool = true
    var preferredHealthHistorySyncRangeRaw: String?
    var preferredAppearanceRaw: String?
    var preferredLanguageRaw: String?

    // Phase 9 optional timer feedback settings (non-destructive)
    var timerNotificationsEnabled: Bool?
    var timerFinishedNotificationEnabled: Bool?
    var awayTooLongEnabled: Bool?
    var awayTooLongMinutes: Int?
    var countdownHapticsEnabled: Bool?
    var hapticAt30: Bool?
    var hapticAt15: Bool?
    var hapticAt5: Bool?
    
    init(name: String, isDemo: Bool = false) {
        let timestamp = Date()
        self.name = name
        self.isDemo = isDemo
        self.remoteSyncEnabled = !isDemo
        self.timestamp = timestamp
        self.lastLogin = timestamp
        self.createdAt = timestamp
        self.updatedAt = timestamp
    }

    var globalProgressionEnabled: Bool {
        get { globalProgressionEnabledStored ?? false }
        set { globalProgressionEnabledStored = newValue }
    }

    var onboardingStatus: UserOnboardingStatus {
        get { UserOnboardingStatus(rawValue: onboardingStatusRaw ?? "") ?? .completed }
        set { onboardingStatusRaw = newValue.rawValue }
    }

    var onboardingGoals: Set<OnboardingGoal> {
        get { Set(onboardingGoalsRaw.compactMap(OnboardingGoal.init(rawValue:))) }
        set { onboardingGoalsRaw = OnboardingGoal.allCases.filter { newValue.contains($0) }.map(\.rawValue) }
    }

    var trainingExperience: OnboardingExperienceLevel? {
        get {
            guard let trainingExperienceRaw else { return nil }
            return OnboardingExperienceLevel(rawValue: trainingExperienceRaw)
        }
        set { trainingExperienceRaw = newValue?.rawValue }
    }

    var needsOnboarding: Bool {
        !isDemo && onboardingStatus != .completed
    }

    var preferredAppearance: AppAppearancePreference {
        get {
            guard let preferredAppearanceRaw else { return .system }
            return AppAppearancePreference(rawValue: preferredAppearanceRaw) ?? .system
        }
        set {
            preferredAppearanceRaw = newValue == .system ? nil : newValue.rawValue
        }
    }

    var preferredLanguage: AppLanguagePreference {
        get {
            guard let preferredLanguageRaw else { return .system }
            return AppLanguagePreference(rawValue: preferredLanguageRaw) ?? .system
        }
        set {
            preferredLanguageRaw = newValue == .system ? nil : newValue.rawValue
        }
    }
}
