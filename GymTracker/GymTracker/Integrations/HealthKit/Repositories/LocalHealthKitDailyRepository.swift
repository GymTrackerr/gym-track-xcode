import Foundation
import SwiftData

final class LocalHealthKitDailyRepository: HealthKitDailyRepositoryProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchCachedSummary(userId: String, dayKey: String) throws -> HealthKitDailyAggregateData? {
        let cacheKey = "\(userId)|\(dayKey)"
        let descriptor = FetchDescriptor<HealthKitDailyAggregateData>(
            predicate: #Predicate<HealthKitDailyAggregateData> { item in
                item.cacheKey == cacheKey && item.soft_deleted == false
            }
        )
        let summary = try modelContext.fetch(descriptor).first
        if let summary, try SyncRootMetadataManager.prepareForRead(summary, in: modelContext) {
            try modelContext.save()
        }
        return summary
    }

    func fetchCachedSummaries(userId: String, from startDay: Date, to endDay: Date) throws -> [String: HealthKitDailyAggregateData] {
        let descriptor = FetchDescriptor<HealthKitDailyAggregateData>(
            predicate: #Predicate<HealthKitDailyAggregateData> { item in
                item.userId == userId && item.soft_deleted == false && item.dayStart >= startDay && item.dayStart <= endDay
            }
        )
        let items = try modelContext.fetch(descriptor)
        if try SyncRootMetadataManager.prepareForRead(items, in: modelContext) {
            try modelContext.save()
        }
        return Dictionary(uniqueKeysWithValues: items.map { ($0.dayKey, $0) })
    }

    func fetchCachedSummaries(userId: String) throws -> [HealthKitDailyAggregateData] {
        let descriptor = FetchDescriptor<HealthKitDailyAggregateData>(
            predicate: #Predicate<HealthKitDailyAggregateData> { item in
                item.userId == userId && item.soft_deleted == false
            },
            sortBy: [SortDescriptor(\.dayStart)]
        )
        let items = try modelContext.fetch(descriptor)
        if try SyncRootMetadataManager.prepareForRead(items, in: modelContext) {
            try modelContext.save()
        }
        return items
    }

    func upsertCache(
        with dto: HealthKitDailyAggregateData,
        refreshedAt: Date,
        isToday: Bool,
        saveImmediately: Bool = true
    ) throws {
        if let existing = try fetchCachedSummary(userId: dto.userId, dayKey: dto.dayKey) {
            existing.dayStart = dto.dayStart
            existing.steps = dto.steps
            existing.activeEnergyKcal = dto.activeEnergyKcal
            existing.restingEnergyKcal = dto.restingEnergyKcal
            existing.exerciseMinutes = dto.exerciseMinutes
            existing.standHours = dto.standHours
            existing.moveGoalKcal = dto.moveGoalKcal
            existing.exerciseGoalMinutes = dto.exerciseGoalMinutes
            existing.standGoalHours = dto.standGoalHours
            existing.sleepSeconds = dto.sleepSeconds
            existing.bodyWeightKg = dto.bodyWeightKg
            existing.schemaVersion = dto.schemaVersion
            existing.lastRefreshedAt = refreshedAt
            existing.isToday = isToday
            existing.soft_deleted = false
            try SyncRootMetadataManager.markUpdated(existing, in: modelContext)
        } else {
            dto.lastRefreshedAt = refreshedAt
            dto.isToday = isToday
            modelContext.insert(dto)
            try SyncRootMetadataManager.markCreated(dto, in: modelContext)
        }

        if saveImmediately {
            try modelContext.save()
        }
    }

    func saveChanges() throws {
        try modelContext.save()
    }
}
