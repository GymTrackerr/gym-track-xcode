import Foundation

final class NutritionLogSyncRepository: BaseSyncRepository, NutritionLogRepositoryProtocol {
    private let localRepository: NutritionLogRepositoryProtocol

    init(
        localRepository: NutritionLogRepositoryProtocol,
        queueStore: SyncQueueStore,
        eligibilityService: SyncEligibilityService
    ) {
        self.localRepository = localRepository
        super.init(queueStore: queueStore, eligibilityService: eligibilityService)
    }

    func fetchNutritionLogs(for userId: UUID, between start: Date, and end: Date) throws -> [NutritionLogEntry] {
        try localRepository.fetchNutritionLogs(for: userId, between: start, and: end)
    }

    func fetchNutritionLogs(for userId: UUID, in interval: DateInterval) throws -> [NutritionLogEntry] {
        try localRepository.fetchNutritionLogs(for: userId, in: interval)
    }

    func insertNutritionLogEntry(_ log: NutritionLogEntry) throws {
        try localRepository.insertNutritionLogEntry(log)
        enqueueRootMutationIfNeeded(root: log, operation: .create)
    }

    func saveNutritionLogEntry(_ log: NutritionLogEntry) throws {
        try localRepository.saveNutritionLogEntry(log)
        enqueueRootMutationIfNeeded(root: log, operation: .update)
    }

    func softDeleteNutritionLogEntry(_ log: NutritionLogEntry) throws {
        try localRepository.softDeleteNutritionLogEntry(log)
        enqueueRootMutationIfNeeded(root: log, operation: .softDelete)
    }
}
