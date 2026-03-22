import Foundation
import SwiftData
import SwiftUI
import Combine

enum HealthDataFetchPolicy {
    case cachedOnly
    case refreshIfStale
    case forceRefresh
}

@MainActor
final class HealthKitDailyStore: ServiceBase, ObservableObject {
    enum StoreError: LocalizedError {
        case cacheMiss

        var errorDescription: String? {
            switch self {
            case .cacheMiss:
                return "No cached health data found for this day."
            }
        }
    }

    static let currentSourceVersion = 1
    private let staleInterval: TimeInterval = 15 * 60

    @Published private(set) var refreshToken: Int = 0

    private let healthKitManager: HealthKitManager
    private let dateNormalizer: HealthKitDateNormalizer
    private var inFlightTasks: [String: Task<HealthKitDailyAggregateData, Error>] = [:]

    init(
        context: ModelContext,
        healthKitManager: HealthKitManager,
        dateNormalizer: HealthKitDateNormalizer
    ) {
        self.healthKitManager = healthKitManager
        self.dateNormalizer = dateNormalizer
        super.init(context: context)
    }

    func dailySummary(
        for day: Date,
        userId: String,
        policy: HealthDataFetchPolicy = .refreshIfStale
    ) async throws -> HealthKitDailyAggregateData {
        let dayStart = dateNormalizer.startOfDay(day)
        let dayKey = dateNormalizer.dayKey(dayStart)

        let cached = try fetchCachedSummary(userId: userId, dayKey: dayKey)

        switch policy {
        case .cachedOnly:
            guard let cached else { throw StoreError.cacheMiss }
            return mapToDTO(cached)

        case .refreshIfStale:
            if let cached, !shouldRefresh(cached: cached, dayStart: dayStart) {
                return mapToDTO(cached)
            }
            return try await refreshDay(dayStart: dayStart, userId: userId)

        case .forceRefresh:
            return try await refreshDay(dayStart: dayStart, userId: userId)
        }
    }

    func dailySummaries(
        endingOn endDate: Date,
        days: Int,
        userId: String,
        policy: HealthDataFetchPolicy = .refreshIfStale
    ) async throws -> [HealthKitDailyAggregateData] {
        let dates = dateNormalizer.buildDateRange(endingOn: endDate, days: days)
        var summaries: [HealthKitDailyAggregateData] = []
        summaries.reserveCapacity(dates.count)

        for day in dates {
            let summary = try await dailySummary(for: day, userId: userId, policy: policy)
            summaries.append(summary)
        }

        return summaries
    }

    func refreshTodayIfNeeded(userId: String) async {
        _ = try? await dailySummary(for: Date(), userId: userId, policy: .refreshIfStale)
    }

    func invalidateDay(for day: Date, userId: String) throws {
        let dayKey = dateNormalizer.dayKey(day)
        guard let cached = try fetchCachedSummary(userId: userId, dayKey: dayKey) else { return }
        cached.isComplete = false
        cached.lastRefreshedAt = .distantPast
        try modelContext.save()
        refreshToken &+= 1
    }

    func invalidateAll(userId: String) throws {
        let descriptor = FetchDescriptor<HealthKitDailySummaryCache>(
            predicate: #Predicate<HealthKitDailySummaryCache> { item in
                item.userId == userId
            }
        )
        let cachedItems = try modelContext.fetch(descriptor)
        for item in cachedItems {
            item.isComplete = false
            item.lastRefreshedAt = .distantPast
        }
        try modelContext.save()
    }

    private func refreshDay(dayStart: Date, userId: String) async throws -> HealthKitDailyAggregateData {
        let cacheKey = makeCacheKey(userId: userId, dayKey: dateNormalizer.dayKey(dayStart))

        if let existingTask = inFlightTasks[cacheKey] {
            return try await existingTask.value
        }

        let task = Task<HealthKitDailyAggregateData, Error> {
            let dto = try await self.healthKitManager.fetchDailyAggregate(for: dayStart, userId: userId)
            try self.upsertCache(with: dto)
            return dto
        }

        inFlightTasks[cacheKey] = task
        defer { inFlightTasks[cacheKey] = nil }
        return try await task.value
    }

    private func shouldRefresh(cached: HealthKitDailySummaryCache, dayStart: Date) -> Bool {
        if cached.sourceVersion != Self.currentSourceVersion {
            return true
        }

        let isToday = dateNormalizer.sameDay(dayStart, Date())
        if isToday {
            let age = Date().timeIntervalSince(cached.lastRefreshedAt)
            if age > staleInterval {
                return true
            }
            return !cached.isComplete
        }

        return !cached.isComplete
    }

    private func fetchCachedSummary(userId: String, dayKey: String) throws -> HealthKitDailySummaryCache? {
        let cacheKey = makeCacheKey(userId: userId, dayKey: dayKey)
        let descriptor = FetchDescriptor<HealthKitDailySummaryCache>(
            predicate: #Predicate<HealthKitDailySummaryCache> { item in
                item.cacheKey == cacheKey
            }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func upsertCache(with dto: HealthKitDailyAggregateData) throws {
        let refreshedAt = Date()
        let isToday = dateNormalizer.sameDay(dto.dayStart, Date())
        let isComplete = !isToday

        if let existing = try fetchCachedSummary(userId: dto.userId, dayKey: dto.dayKey) {
            existing.dayStart = dto.dayStart
            existing.steps = dto.steps
            existing.activeEnergyKcal = dto.activeEnergyKcal
            existing.restingEnergyKcal = dto.restingEnergyKcal
            existing.sleepSeconds = dto.sleepSeconds
            existing.lastRefreshedAt = refreshedAt
            existing.isComplete = isComplete
            existing.sourceVersion = Self.currentSourceVersion
        } else {
            let cache = HealthKitDailySummaryCache(
                userId: dto.userId,
                dayKey: dto.dayKey,
                dayStart: dto.dayStart,
                steps: dto.steps,
                activeEnergyKcal: dto.activeEnergyKcal,
                restingEnergyKcal: dto.restingEnergyKcal,
                sleepSeconds: dto.sleepSeconds,
                lastRefreshedAt: refreshedAt,
                isComplete: isComplete,
                sourceVersion: Self.currentSourceVersion
            )
            modelContext.insert(cache)
        }

        try modelContext.save()
    }

    private func mapToDTO(_ cache: HealthKitDailySummaryCache) -> HealthKitDailyAggregateData {
        HealthKitDailyAggregateData(
            userId: cache.userId,
            dayKey: cache.dayKey,
            dayStart: cache.dayStart,
            steps: cache.steps,
            activeEnergyKcal: cache.activeEnergyKcal,
            restingEnergyKcal: cache.restingEnergyKcal,
            sleepSeconds: cache.sleepSeconds
        )
    }

    private func makeCacheKey(userId: String, dayKey: String) -> String {
        "\(userId)|\(dayKey)"
    }
}
