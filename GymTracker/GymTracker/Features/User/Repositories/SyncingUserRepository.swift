import Foundation

final class SyncingUserRepository: UserRepositoryProtocol {
    private let localRepository: UserRepositoryProtocol
    private let queueStore: SyncQueueStore
    private let eligibilityService: SyncEligibilityService

    init(
        localRepository: UserRepositoryProtocol,
        queueStore: SyncQueueStore,
        eligibilityService: SyncEligibilityService
    ) {
        self.localRepository = localRepository
        self.queueStore = queueStore
        self.eligibilityService = eligibilityService
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
        SyncQueueMutationWriter.enqueueIfNeeded(
            root: user,
            operation: operation,
            queueStore: queueStore,
            eligibilityService: eligibilityService
        )
    }
}
