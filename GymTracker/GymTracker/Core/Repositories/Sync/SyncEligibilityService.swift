//
//  SyncEligibilityService.swift
//  GymTracker
//
//  Created by Codex on 2026-04-15.
//

import Foundation
import Combine

struct SyncEligibilitySnapshot: Equatable {
    let syncFeatureEnabled: Bool
    let networkAvailable: Bool
    let authAvailable: Bool
    let hasActiveLocalUser: Bool

    var isQueueingAllowed: Bool {
        syncFeatureEnabled && authAvailable && hasActiveLocalUser
    }

    var isProcessingEligible: Bool {
        isQueueingAllowed && networkAvailable
    }
}

final class SyncEligibilityService: ObservableObject {
    @Published private(set) var snapshot: SyncEligibilitySnapshot

    private let eligibilityState: SyncEligibilityState
    private let userDefaults: UserDefaults
    private let syncFeatureEnabledKey = "gymtracker.sync.feature.enabled"
    private var cancellables = Set<AnyCancellable>()

    init(
        eligibilityState: SyncEligibilityState,
        userDefaults: UserDefaults = .standard
    ) {
        self.eligibilityState = eligibilityState
        self.userDefaults = userDefaults

        let syncFeatureEnabled = userDefaults.object(forKey: syncFeatureEnabledKey) as? Bool ?? false
        eligibilityState.backendEnabled = syncFeatureEnabled
        self.snapshot = SyncEligibilitySnapshot(
            syncFeatureEnabled: syncFeatureEnabled,
            networkAvailable: eligibilityState.networkAvailable,
            authAvailable: eligibilityState.authAvailable,
            hasActiveLocalUser: eligibilityState.hasActiveLocalUser
        )

        bindEligibilityState()
    }

    var isQueueingAllowed: Bool {
        snapshot.isQueueingAllowed
    }

    var isProcessingEligible: Bool {
        snapshot.isProcessingEligible
    }

    func setSyncFeatureEnabled(_ enabled: Bool) {
        userDefaults.set(enabled, forKey: syncFeatureEnabledKey)
        eligibilityState.backendEnabled = enabled
        refreshSnapshot()
    }

    private func bindEligibilityState() {
        Publishers.CombineLatest4(
            eligibilityState.$backendEnabled,
            eligibilityState.$networkAvailable,
            eligibilityState.$authAvailable,
            eligibilityState.$hasActiveLocalUser
        )
        .sink { [weak self] _, _, _, _ in
            self?.refreshSnapshot()
        }
        .store(in: &cancellables)
    }

    private func refreshSnapshot() {
        snapshot = SyncEligibilitySnapshot(
            syncFeatureEnabled: eligibilityState.backendEnabled,
            networkAvailable: eligibilityState.networkAvailable,
            authAvailable: eligibilityState.authAvailable,
            hasActiveLocalUser: eligibilityState.hasActiveLocalUser
        )
    }
}
