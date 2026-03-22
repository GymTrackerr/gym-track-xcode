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

    private let staleInterval: TimeInterval = 15 * 60
    private let batchingThreshold = 3

    private struct DailyAggregateSnapshot: Sendable {
        let userId: String
        let dayKey: String
        let dayStart: Date
        let steps: Double
        let activeEnergyKcal: Double
        let restingEnergyKcal: Double
        let sleepSeconds: TimeInterval

        init(from aggregate: HealthKitDailyAggregateData) {
            self.userId = aggregate.userId
            self.dayKey = aggregate.dayKey
            self.dayStart = aggregate.dayStart
            self.steps = aggregate.steps
            self.activeEnergyKcal = aggregate.activeEnergyKcal
            self.restingEnergyKcal = aggregate.restingEnergyKcal
            self.sleepSeconds = aggregate.sleepSeconds
        }

        func asAggregate() -> HealthKitDailyAggregateData {
            HealthKitDailyAggregateData(
                userId: userId,
                dayKey: dayKey,
                dayStart: dayStart,
                steps: steps,
                activeEnergyKcal: activeEnergyKcal,
                restingEnergyKcal: restingEnergyKcal,
                sleepSeconds: sleepSeconds
            )
        }
    }

    @Published private(set) var refreshToken: Int = 0
    @Published private(set) var isBackfillingHistory: Bool = false
    @Published private(set) var backfillStatusText: String = ""

    private let healthKitManager: HealthKitManager
    private let dateNormalizer: HealthKitDateNormalizer
    private var inFlightTasks: [String: Task<DailyAggregateSnapshot, Error>] = [:]

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
        guard interval.end > interval.start else { return [] }
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
        let descriptor = FetchDescriptor<HealthKitDailyAggregateData>(
            predicate: #Predicate<HealthKitDailyAggregateData> { item in
                item.userId == userId
            },
            sortBy: [SortDescriptor(\.dayStart)]
        )
        let items = try modelContext.fetch(descriptor)
        return (items.first?.dayStart, items.last?.dayStart)
    }

    func cachedDailySummaries(userId: String) throws -> [HealthKitDailyAggregateData] {
        let descriptor = FetchDescriptor<HealthKitDailyAggregateData>(
            predicate: #Predicate<HealthKitDailyAggregateData> { item in
                item.userId == userId
            },
            sortBy: [SortDescriptor(\.dayStart)]
        )
        let items = try modelContext.fetch(descriptor)
        return items
    }

    func cachedDailySummaries(
        in interval: DateInterval,
        userId: String
    ) throws -> [HealthKitDailyAggregateData] {
        guard interval.end > interval.start else { return [] }
        let dayStarts = dayStarts(in: interval)
        guard !dayStarts.isEmpty else { return [] }

        let rangeStart = dayStarts.first ?? dateNormalizer.startOfDay(interval.start)
        let rangeEnd = dayStarts.last ?? rangeStart
        let cachedByDayKey = try fetchCachedSummaries(userId: userId, from: rangeStart, to: rangeEnd)

        return dayStarts.map { dayStart in
            let dayKey = dateNormalizer.dayKey(dayStart)
            if let cached = cachedByDayKey[dayKey] {
                return mapToDTO(cached)
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

    func backfillHistoryIfNeeded(
        userId: String,
        maxYearsBack: Int = 25,
        chunkDays: Int = 180,
        emptyChunkStop: Int = 4
    ) async -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let absoluteStart = calendar.date(byAdding: .year, value: -maxYearsBack, to: now) ?? now
        let bounds = try? cachedDataBounds(userId: userId)
        let initialEnd = (bounds?.oldest ?? now).addingTimeInterval(-24 * 60 * 60)

        if initialEnd <= absoluteStart {
            return true
        }

        isBackfillingHistory = true
        backfillStatusText = "Loading HealthKit history..."
        defer {
            isBackfillingHistory = false
            backfillStatusText = ""
        }

        let requestedTotalDays = max((calendar.dateComponents([.day], from: absoluteStart, to: initialEnd).day ?? 0) + 1, 1)
        var cursorEnd = initialEnd
        var processedDays = 0
        var wroteAnyData = false
        var foundAnyData = false
        var emptyChunkStreak = 0

        while cursorEnd > absoluteStart {
            if Task.isCancelled { return false }
            await Task.yield()

            let daysCovered = max((calendar.dateComponents([.day], from: absoluteStart, to: cursorEnd).day ?? 0) + 1, 1)
            let requestDays = min(chunkDays, daysCovered)

            let progress = min(Int((Double(processedDays) / Double(requestedTotalDays)) * 100.0), 99)
            backfillStatusText = "Loading HealthKit history... \(progress)%"

            if let summaries = try? await dailySummaries(
                endingOn: cursorEnd,
                days: requestDays,
                userId: userId,
                policy: .refreshIfStale
            ) {
                wroteAnyData = true
                let chunkHasData = summaries.contains { summary in
                    summary.steps > 0 ||
                    summary.activeEnergyKcal > 0 ||
                    summary.restingEnergyKcal > 0 ||
                    summary.sleepSeconds > 0
                }

                if chunkHasData {
                    foundAnyData = true
                    emptyChunkStreak = 0
                } else if foundAnyData {
                    emptyChunkStreak += 1
                    if emptyChunkStreak >= emptyChunkStop {
                        break
                    }
                }
            }

            processedDays += requestDays
            guard let nextEnd = calendar.date(byAdding: .day, value: -requestDays, to: cursorEnd) else {
                break
            }
            cursorEnd = nextEnd
        }

        backfillStatusText = "Loading HealthKit history... 100%"
        if wroteAnyData {
            refreshToken &+= 1
        }
        return true
    }

    func invalidateDay(for day: Date, userId: String) throws {
        let dayKey = dateNormalizer.dayKey(day)
        guard let cached = try fetchCachedSummary(userId: userId, dayKey: dayKey) else { return }
        cached.lastRefreshedAt = .distantPast
        cached.isToday = dateNormalizer.sameDay(cached.dayStart, Date())
        try modelContext.save()
        refreshToken &+= 1
    }

    func invalidateAll(userId: String) throws {
        let descriptor = FetchDescriptor<HealthKitDailyAggregateData>(
            predicate: #Predicate<HealthKitDailyAggregateData> { item in
                item.userId == userId
            }
        )
        let cachedItems = try modelContext.fetch(descriptor)
        for item in cachedItems {
            item.lastRefreshedAt = .distantPast
            item.isToday = dateNormalizer.sameDay(item.dayStart, Date())
        }
        try modelContext.save()
    }

    private func refreshDay(dayStart: Date, userId: String) async throws -> HealthKitDailyAggregateData {
        let cacheKey = makeCacheKey(userId: userId, dayKey: dateNormalizer.dayKey(dayStart))

        if let existingTask = inFlightTasks[cacheKey] {
            let snapshot = try await existingTask.value
            return try cachedOrSnapshot(snapshot)
        }

        let task = Task<DailyAggregateSnapshot, Error> {
            let dto = try await self.healthKitManager.fetchDailyAggregate(for: dayStart, userId: userId)
            try self.upsertCache(with: dto)
            return DailyAggregateSnapshot(from: dto)
        }

        inFlightTasks[cacheKey] = task
        defer { inFlightTasks[cacheKey] = nil }
        let snapshot = try await task.value
        return try cachedOrSnapshot(snapshot)
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
                let snapshot = try await existing.value
                resolved[dayKey] = snapshot.asAggregate()
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

            let rangeTask = Task<[DailyAggregateSnapshot], Error> {
                let dtos = try await self.healthKitManager.fetchDailyAggregates(
                    from: firstDay,
                    to: lastDay,
                    userId: userId,
                    calendar: .current
                )
                return dtos.map(DailyAggregateSnapshot.init(from:))
            }

            for dayStart in segment {
                let dayKey = dateNormalizer.dayKey(dayStart)
                let cacheKey = makeCacheKey(userId: userId, dayKey: dayKey)
                inFlightTasks[cacheKey] = Task {
                    let snapshots = try await rangeTask.value
                    if let snapshot = snapshots.first(where: { $0.dayKey == dayKey }) {
                        return snapshot
                    }
                    return DailyAggregateSnapshot(from: HealthKitDailyAggregateData(
                        userId: userId,
                        dayKey: dayKey,
                        dayStart: dayStart,
                        steps: 0,
                        activeEnergyKcal: 0,
                        restingEnergyKcal: 0,
                        sleepSeconds: 0
                    ))
                }
            }

            defer {
                for dayKey in segmentKeys {
                    inFlightTasks[makeCacheKey(userId: userId, dayKey: dayKey)] = nil
                }
            }

            let snapshots = try await rangeTask.value
            for snapshot in snapshots {
                let dto = snapshot.asAggregate()
                try upsertCache(with: dto, saveImmediately: false)
                resolved[snapshot.dayKey] = dto
            }
            if !snapshots.isEmpty {
                try modelContext.save()
            }
        }

        return resolved
    }

    private func shouldRefresh(cached: HealthKitDailyAggregateData, dayStart: Date) -> Bool {
        if dateNormalizer.sameDay(dayStart, Date()) {
            let age = Date().timeIntervalSince(cached.lastRefreshedAt)
            return age > staleInterval
        }
        return cached.lastRefreshedAt == .distantPast
    }

    private func fetchCachedSummary(userId: String, dayKey: String) throws -> HealthKitDailyAggregateData? {
        let cacheKey = makeCacheKey(userId: userId, dayKey: dayKey)
        let descriptor = FetchDescriptor<HealthKitDailyAggregateData>(
            predicate: #Predicate<HealthKitDailyAggregateData> { item in
                item.cacheKey == cacheKey
            }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func fetchCachedSummaries(
        userId: String,
        from startDay: Date,
        to endDay: Date
    ) throws -> [String: HealthKitDailyAggregateData] {
        let descriptor = FetchDescriptor<HealthKitDailyAggregateData>(
            predicate: #Predicate<HealthKitDailyAggregateData> { item in
                item.userId == userId && item.dayStart >= startDay && item.dayStart <= endDay
            }
        )
        let items = try modelContext.fetch(descriptor)
        return Dictionary(uniqueKeysWithValues: items.map { ($0.dayKey, $0) })
    }

    private func upsertCache(with dto: HealthKitDailyAggregateData, saveImmediately: Bool = true) throws {
        let refreshedAt = Date()
        let isToday = dateNormalizer.sameDay(dto.dayStart, Date())

        if let existing = try fetchCachedSummary(userId: dto.userId, dayKey: dto.dayKey) {
            existing.dayStart = dto.dayStart
            existing.steps = dto.steps
            existing.activeEnergyKcal = dto.activeEnergyKcal
            existing.restingEnergyKcal = dto.restingEnergyKcal
            existing.sleepSeconds = dto.sleepSeconds
            existing.lastRefreshedAt = refreshedAt
            existing.isToday = isToday
        } else {
            dto.lastRefreshedAt = refreshedAt
            dto.isToday = isToday
            modelContext.insert(dto)
        }

        if saveImmediately {
            try modelContext.save()
        }
    }

    private func mapToDTO(_ cache: HealthKitDailyAggregateData) -> HealthKitDailyAggregateData {
        cache
    }

    private func cachedOrSnapshot(_ snapshot: DailyAggregateSnapshot) throws -> HealthKitDailyAggregateData {
        if let cached = try fetchCachedSummary(userId: snapshot.userId, dayKey: snapshot.dayKey) {
            return mapToDTO(cached)
        }
        return snapshot.asAggregate()
    }

    private func makeCacheKey(userId: String, dayKey: String) -> String {
        "\(userId)|\(dayKey)"
    }

    private func dayStarts(in interval: DateInterval) -> [Date] {
        guard interval.end > interval.start else { return [] }
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
