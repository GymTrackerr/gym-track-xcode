//
//  UserSyncRepository.swift
//  GymTracker
//
//  Created by Codex on 2026-04-16.
//

import Foundation

final class UserSyncRepository: BaseSyncRepository, UserRepositoryProtocol {
    private let localRepository: UserRepositoryProtocol

    init(
        localRepository: UserRepositoryProtocol,
        queueStore: SyncQueueStore,
        eligibilityService: SyncEligibilityService
    ) {
        self.localRepository = localRepository
        super.init(queueStore: queueStore, eligibilityService: eligibilityService)
    }

    func fetchAccounts() throws -> [User] { try localRepository.fetchAccounts() }

    func createUser(name: String, isDemo: Bool) throws -> User {
        let user = try localRepository.createUser(name: name, isDemo: isDemo)
        enqueue(for: user, operation: .create)
        return user
    }

    func delete(_ user: User) throws {
        try localRepository.delete(user)
        enqueue(for: user, operation: .softDelete)
    }

    func saveChanges(for user: User) throws {
        try localRepository.saveChanges(for: user)
        enqueue(for: user, operation: .update)
    }

    private func enqueue(for user: User, operation: SyncQueueOperation) {
        enqueueRootMutationIfNeeded(root: user, operation: operation)
    }
}
