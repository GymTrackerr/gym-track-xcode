import Foundation

final class HealthKitDailySyncRepository: BaseSyncRepository, HealthKitDailyRepositoryProtocol {
    private let localRepository: HealthKitDailyRepositoryProtocol
    private var pendingMutations: [(dto: HealthKitDailyAggregateData, operation: SyncQueueOperation)] = []

    init(
        localRepository: HealthKitDailyRepositoryProtocol,
        queueStore: SyncQueueStore,
        eligibilityService: SyncEligibilityService
    ) {
        self.localRepository = localRepository
        super.init(queueStore: queueStore, eligibilityService: eligibilityService)
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

    func fetchCachedBounds(userId: String) throws -> (oldest: Date?, newest: Date?) {
        try localRepository.fetchCachedBounds(userId: userId)
    }

    func fetchUnsyncedPastSummaries(userId: String, before dayStart: Date, limit: Int) throws -> [HealthKitDailyAggregateData] {
        try localRepository.fetchUnsyncedPastSummaries(userId: userId, before: dayStart, limit: limit)
    }

    func upsertCache(
        with dto: HealthKitDailyAggregateData,
        refreshedAt: Date,
        isToday: Bool,
        isFullySynced: Bool,
        saveImmediately: Bool
    ) throws {
        let existing = try localRepository.fetchCachedSummary(userId: dto.userId, dayKey: dto.dayKey)
        try localRepository.upsertCache(
            with: dto,
            refreshedAt: refreshedAt,
            isToday: isToday,
            isFullySynced: isFullySynced,
            saveImmediately: saveImmediately
        )
        let operation: SyncQueueOperation = existing == nil ? .create : .update
        if saveImmediately {
            enqueueRootMutationIfNeeded(root: dto, operation: operation)
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
            enqueueRootMutationIfNeeded(root: mutation.dto, operation: mutation.operation)
        }
    }
}
