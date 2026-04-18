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
        syncFeatureEnabled && hasActiveLocalUser
    }

    var isProcessingEligible: Bool {
        isQueueingAllowed && authAvailable && networkAvailable
    }
}

final class SyncEligibilityService: ObservableObject {
    @Published private(set) var snapshot: SyncEligibilitySnapshot

    private let eligibilityState: SyncEligibilityState
    private var cancellables = Set<AnyCancellable>()

    init(eligibilityState: SyncEligibilityState) {
        self.eligibilityState = eligibilityState
        self.snapshot = SyncEligibilitySnapshot(
            syncFeatureEnabled: eligibilityState.backendEnabled,
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
