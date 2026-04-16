import Foundation

protocol HealthKitDailyRepositoryProtocol {
    func fetchCachedSummary(userId: String, dayKey: String) throws -> HealthKitDailyAggregateData?
    func fetchCachedSummaries(userId: String, from startDay: Date, to endDay: Date) throws -> [String: HealthKitDailyAggregateData]
    func fetchCachedSummaries(userId: String) throws -> [HealthKitDailyAggregateData]
    func fetchUnsyncedPastSummaries(userId: String, before dayStart: Date, limit: Int) throws -> [HealthKitDailyAggregateData]
    func upsertCache(
        with dto: HealthKitDailyAggregateData,
        refreshedAt: Date,
        isToday: Bool,
        isFullySynced: Bool,
        saveImmediately: Bool
    ) throws
    func saveChanges() throws
}
