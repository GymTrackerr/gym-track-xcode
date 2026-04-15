import Foundation

final class SyncingNutritionLogRepository: NutritionLogRepositoryProtocol {
    private let localRepository: NutritionLogRepositoryProtocol
    private let queueStore: SyncQueueStore
    private let eligibilityService: SyncEligibilityService

    init(
        localRepository: NutritionLogRepositoryProtocol,
        queueStore: SyncQueueStore,
        eligibilityService: SyncEligibilityService
    ) {
        self.localRepository = localRepository
        self.queueStore = queueStore
        self.eligibilityService = eligibilityService
    }

    func fetchNutritionLogs(for userId: UUID, between start: Date, and end: Date) throws -> [NutritionLogEntry] {
        try localRepository.fetchNutritionLogs(for: userId, between: start, and: end)
    }

    func fetchNutritionLogs(for userId: UUID, in interval: DateInterval) throws -> [NutritionLogEntry] {
        try localRepository.fetchNutritionLogs(for: userId, in: interval)
    }

    func insertNutritionLogEntry(_ log: NutritionLogEntry) throws {
        try localRepository.insertNutritionLogEntry(log)
        SyncQueueMutationWriter.enqueueIfNeeded(
            root: log,
            operation: .create,
            queueStore: queueStore,
            eligibilityService: eligibilityService
        )
    }

    func saveNutritionLogEntry(_ log: NutritionLogEntry) throws {
        try localRepository.saveNutritionLogEntry(log)
        SyncQueueMutationWriter.enqueueIfNeeded(
            root: log,
            operation: .update,
            queueStore: queueStore,
            eligibilityService: eligibilityService
        )
    }

    func softDeleteNutritionLogEntry(_ log: NutritionLogEntry) throws {
        try localRepository.softDeleteNutritionLogEntry(log)
        SyncQueueMutationWriter.enqueueIfNeeded(
            root: log,
            operation: .softDelete,
            queueStore: queueStore,
            eligibilityService: eligibilityService
        )
    }
}
