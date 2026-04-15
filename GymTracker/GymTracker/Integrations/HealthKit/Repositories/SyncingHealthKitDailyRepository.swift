import Foundation

final class SyncingHealthKitDailyRepository: HealthKitDailyRepositoryProtocol {
    private let localRepository: HealthKitDailyRepositoryProtocol
    private let queueStore: SyncQueueStore
    private let eligibilityService: SyncEligibilityService
    private var pendingMutations: [(dto: HealthKitDailyAggregateData, operation: SyncQueueOperation)] = []

    init(
        localRepository: HealthKitDailyRepositoryProtocol,
        queueStore: SyncQueueStore,
        eligibilityService: SyncEligibilityService
    ) {
        self.localRepository = localRepository
        self.queueStore = queueStore
        self.eligibilityService = eligibilityService
    }

    func fetchCachedSummary(userId: String, dayKey: String) throws -> HealthKitDailyAggregateData? {
        try localRepository.fetchCachedSummary(userId: userId, dayKey: dayKey)
    }

    func fetchCachedSummaries(userId: String, from startDay: Date, to endDay: Date) throws -> [String: HealthKitDailyAggregateData] {
        try localRepository.fetchCachedSummaries(userId: userId, from: startDay, to: endDay)
    }

    func fetchCachedSummaries(userId: String) throws -> [HealthKitDailyAggregateData] {
        try localRepository.fetchCachedSummaries(userId: userId)
    }

    func upsertCache(
        with dto: HealthKitDailyAggregateData,
        refreshedAt: Date,
        isToday: Bool,
        saveImmediately: Bool
    ) throws {
        let existing = try localRepository.fetchCachedSummary(userId: dto.userId, dayKey: dto.dayKey)
        try localRepository.upsertCache(with: dto, refreshedAt: refreshedAt, isToday: isToday, saveImmediately: saveImmediately)
        let operation: SyncQueueOperation = existing == nil ? .create : .update
        if saveImmediately {
            SyncQueueMutationWriter.enqueueIfNeeded(
                root: dto,
                operation: operation,
                queueStore: queueStore,
                eligibilityService: eligibilityService
            )
        } else {
            pendingMutations.append((dto: dto, operation: operation))
        }
    }

    func saveChanges() throws {
        try localRepository.saveChanges()
        guard pendingMutations.isEmpty == false else { return }

        let mutations = pendingMutations
        pendingMutations.removeAll()
        for mutation in mutations {
            SyncQueueMutationWriter.enqueueIfNeeded(
                root: mutation.dto,
                operation: mutation.operation,
                queueStore: queueStore,
                eligibilityService: eligibilityService
            )
        }
    }
}
