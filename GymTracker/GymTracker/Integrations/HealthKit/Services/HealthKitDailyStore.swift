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
    private let batchingThreshold = 3

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
        let normalizedDays = max(days, 1)
        let endDay = dateNormalizer.startOfDay(endDate)
        let startDay = Calendar.current.date(byAdding: .day, value: -(normalizedDays - 1), to: endDay) ?? endDay
        let intervalEndExclusive = Calendar.current.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        let interval = DateInterval(start: startDay, end: intervalEndExclusive)
        return try await dailySummaries(in: interval, userId: userId, policy: policy)
    }

    func dailySummaries(
        in interval: DateInterval,
        userId: String,
        policy: HealthDataFetchPolicy = .refreshIfStale
    ) async throws -> [HealthKitDailyAggregateData] {
        let dayStarts = dayStarts(in: interval)
        guard !dayStarts.isEmpty else { return [] }

        let rangeStart = dayStarts.first ?? dateNormalizer.startOfDay(interval.start)
        let rangeEnd = dayStarts.last ?? rangeStart
        let cachedByDayKey = try fetchCachedSummaries(userId: userId, from: rangeStart, to: rangeEnd)

        var resolved: [String: HealthKitDailyAggregateData] = [:]
        var refreshCandidates: [Date] = []

        for dayStart in dayStarts {
            let dayKey = dateNormalizer.dayKey(dayStart)
            let cached = cachedByDayKey[dayKey]

            switch policy {
            case .cachedOnly:
                guard let cached else { throw StoreError.cacheMiss }
                resolved[dayKey] = mapToDTO(cached)

            case .refreshIfStale:
                if let cached, !shouldRefresh(cached: cached, dayStart: dayStart) {
                    resolved[dayKey] = mapToDTO(cached)
                } else {
                    refreshCandidates.append(dayStart)
                }

            case .forceRefresh:
                refreshCandidates.append(dayStart)
            }
        }

        if !refreshCandidates.isEmpty {
            let refreshed = try await refreshDays(refreshCandidates, userId: userId)
            for (dayKey, dto) in refreshed {
                resolved[dayKey] = dto
            }
        }

        return dayStarts.map { dayStart in
            let dayKey = dateNormalizer.dayKey(dayStart)
            if let existing = resolved[dayKey] {
                return existing
            }
            return HealthKitDailyAggregateData(
                userId: userId,
                dayKey: dayKey,
                dayStart: dayStart,
                steps: 0,
                activeEnergyKcal: 0,
                restingEnergyKcal: 0,
                sleepSeconds: 0
            )
        }
    }

    func refreshTodayIfNeeded(userId: String) async {
        _ = try? await dailySummary(for: Date(), userId: userId, policy: .refreshIfStale)
    }

    func cachedDataBounds(userId: String) throws -> (oldest: Date?, newest: Date?) {
        let descriptor = FetchDescriptor<HealthKitDailySummaryCache>(
            predicate: #Predicate<HealthKitDailySummaryCache> { item in
                item.userId == userId
            },
            sortBy: [SortDescriptor(\.dayStart)]
        )
        let items = try modelContext.fetch(descriptor)
        return (items.first?.dayStart, items.last?.dayStart)
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

    private func refreshDays(_ dayStarts: [Date], userId: String) async throws -> [String: HealthKitDailyAggregateData] {
        let sortedUnique = Array(Set(dayStarts.map { dateNormalizer.startOfDay($0) })).sorted()
        var resolved: [String: HealthKitDailyAggregateData] = [:]

        for block in contiguousBlocks(from: sortedUnique) {
            if block.count >= batchingThreshold {
                let batched = try await refreshContiguousBlock(block, userId: userId)
                for (key, value) in batched { resolved[key] = value }
            } else {
                for dayStart in block {
                    let dto = try await refreshDay(dayStart: dayStart, userId: userId)
                    resolved[dto.dayKey] = dto
                }
            }
        }

        return resolved
    }

    private func refreshContiguousBlock(
        _ dayStarts: [Date],
        userId: String
    ) async throws -> [String: HealthKitDailyAggregateData] {
        var resolved: [String: HealthKitDailyAggregateData] = [:]
        var pending: [Date] = []

        for dayStart in dayStarts {
            let dayKey = dateNormalizer.dayKey(dayStart)
            let cacheKey = makeCacheKey(userId: userId, dayKey: dayKey)
            if let existing = inFlightTasks[cacheKey] {
                let dto = try await existing.value
                resolved[dayKey] = dto
            } else {
                pending.append(dayStart)
            }
        }

        for segment in contiguousBlocks(from: pending) {
            if segment.count < batchingThreshold {
                for dayStart in segment {
                    let dto = try await refreshDay(dayStart: dayStart, userId: userId)
                    resolved[dto.dayKey] = dto
                }
                continue
            }

            let firstDay = segment.first ?? segment[0]
            let lastDay = segment.last ?? segment[0]
            let segmentKeys = segment.map { dateNormalizer.dayKey($0) }

            let rangeTask = Task<[HealthKitDailyAggregateData], Error> {
                try await self.healthKitManager.fetchDailyAggregates(
                    from: firstDay,
                    to: lastDay,
                    userId: userId,
                    calendar: .current
                )
            }

            for dayStart in segment {
                let dayKey = dateNormalizer.dayKey(dayStart)
                let cacheKey = makeCacheKey(userId: userId, dayKey: dayKey)
                inFlightTasks[cacheKey] = Task {
                    let dtos = try await rangeTask.value
                    if let dto = dtos.first(where: { $0.dayKey == dayKey }) {
                        return dto
                    }
                    return HealthKitDailyAggregateData(
                        userId: userId,
                        dayKey: dayKey,
                        dayStart: dayStart,
                        steps: 0,
                        activeEnergyKcal: 0,
                        restingEnergyKcal: 0,
                        sleepSeconds: 0
                    )
                }
            }

            defer {
                for dayKey in segmentKeys {
                    inFlightTasks[makeCacheKey(userId: userId, dayKey: dayKey)] = nil
                }
            }

            let dtos = try await rangeTask.value
            for dto in dtos {
                try upsertCache(with: dto)
                resolved[dto.dayKey] = dto
            }
        }

        return resolved
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

    private func fetchCachedSummaries(
        userId: String,
        from startDay: Date,
        to endDay: Date
    ) throws -> [String: HealthKitDailySummaryCache] {
        let descriptor = FetchDescriptor<HealthKitDailySummaryCache>(
            predicate: #Predicate<HealthKitDailySummaryCache> { item in
                item.userId == userId && item.dayStart >= startDay && item.dayStart <= endDay
            }
        )
        let items = try modelContext.fetch(descriptor)
        return Dictionary(uniqueKeysWithValues: items.map { ($0.dayKey, $0) })
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

    private func dayStarts(in interval: DateInterval) -> [Date] {
        let calendar = Calendar.current
        let startDay = dateNormalizer.startOfDay(interval.start)
        let clampedEnd = interval.end > interval.start ? interval.end.addingTimeInterval(-1) : interval.start
        let endDay = dateNormalizer.startOfDay(clampedEnd)
        let count = (calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0) + 1
        return dateNormalizer.buildDateRange(endingOn: endDay, days: count)
    }

    private func contiguousBlocks(from sortedDays: [Date]) -> [[Date]] {
        guard !sortedDays.isEmpty else { return [] }
        let calendar = Calendar.current
        var blocks: [[Date]] = []
        var currentBlock: [Date] = [sortedDays[0]]

        for day in sortedDays.dropFirst() {
            guard let previous = currentBlock.last else { continue }
            let delta = calendar.dateComponents([.day], from: previous, to: day).day ?? 0
            if delta == 1 {
                currentBlock.append(day)
            } else {
                blocks.append(currentBlock)
                currentBlock = [day]
            }
        }

        blocks.append(currentBlock)
        return blocks
    }
}
