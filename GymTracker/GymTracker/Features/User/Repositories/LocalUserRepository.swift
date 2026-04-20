import Foundation
import SwiftData

final class LocalUserRepository: UserRepositoryProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAccounts() throws -> [User] {
        let descriptor = FetchDescriptor<User>(sortBy: [SortDescriptor(\.lastLogin, order: .reverse)])
        let accounts = try modelContext.fetch(descriptor).filter { !$0.soft_deleted }
        if try SyncRootMetadataManager.prepareForRead(accounts, in: modelContext) {
            try modelContext.save()
        }
        return accounts
    }

    func createUser(name: String, isDemo: Bool = false) throws -> User {
        let user = User(name: name, isDemo: isDemo)
        user.onboardingStatus = isDemo ? .completed : .pending
        modelContext.insert(user)
        try SyncRootMetadataManager.markCreated(user, in: modelContext)
        try modelContext.save()
        return user
    }

    func delete(_ user: User) throws {
        try SyncRootMetadataManager.markSoftDeleted(user, in: modelContext)
        try modelContext.save()
    }

    func saveChanges(for user: User) throws {
        try SyncRootMetadataManager.markUpdated(user, in: modelContext)
        try modelContext.save()
    }
}
