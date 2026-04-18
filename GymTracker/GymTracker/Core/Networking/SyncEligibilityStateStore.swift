//
//  SyncEligibilityStateStore.swift
//  GymTracker
//
//  Created by Codex on 2026-04-16.
//

import Foundation

struct PersistedSyncEligibilitySnapshot: Codable {
    let backendEnabled: Bool
    let networkAvailable: Bool
    let authAvailable: Bool
    let hasActiveLocalUser: Bool
    let updatedAt: Date
}

final class SyncEligibilityStateStore {
    static let shared = SyncEligibilityStateStore()

    private let defaults: UserDefaults
    private let keyPrefix: String

    init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "gymtracker.sync-eligibility."
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    func load(for localUserId: UUID) -> PersistedSyncEligibilitySnapshot? {
        guard let data = defaults.data(forKey: key(for: localUserId)) else { return nil }
        return try? JSONDecoder().decode(PersistedSyncEligibilitySnapshot.self, from: data)
    }

    func save(_ snapshot: PersistedSyncEligibilitySnapshot, for localUserId: UUID) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key(for: localUserId))
    }

    func clear(for localUserId: UUID) {
        defaults.removeObject(forKey: key(for: localUserId))
    }

    private func key(for localUserId: UUID) -> String {
        "\(keyPrefix)\(localUserId.uuidString.lowercased())"
    }
}
