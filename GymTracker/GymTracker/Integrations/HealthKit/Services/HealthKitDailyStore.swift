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
    private var isRunningSchemaUpgrade = false

    private struct DailyAggregateSnapshot: Sendable {
        let userId: String
        let dayKey: String
        let dayStart: Date
        let steps: Double
        let activeEnergyKcal: Double
        let restingEnergyKcal: Double
        let exerciseMinutes: Double
        let standHours: Int
        let moveGoalKcal: Double
        let exerciseGoalMinutes: Double
        let standGoalHours: Int
        let sleepSeconds: TimeInterval
        let bodyWeightKg: Double
        let schemaVersion: Double

        init(from aggregate: HealthKitDailyAggregateData) {
            self.userId = aggregate.userId
            self.dayKey = aggregate.dayKey
            self.dayStart = aggregate.dayStart
            self.steps = aggregate.steps
            self.activeEnergyKcal = aggregate.activeEnergyKcal
            self.restingEnergyKcal = aggregate.restingEnergyKcal
            self.exerciseMinutes = aggregate.exerciseMinutes ?? 0
            self.standHours = aggregate.standHours ?? 0
            self.moveGoalKcal = aggregate.moveGoalKcal ?? 520
            self.exerciseGoalMinutes = aggregate.exerciseGoalMinutes ?? 30
            self.standGoalHours = aggregate.standGoalHours ?? 12
            self.sleepSeconds = aggregate.sleepSeconds
            self.bodyWeightKg = aggregate.bodyWeightKg
            self.schemaVersion = aggregate.schemaVersion
        }

        func asAggregate() -> HealthKitDailyAggregateData {
            HealthKitDailyAggregateData(
                userId: userId,
                dayKey: dayKey,
                dayStart: dayStart,
                steps: steps,
                activeEnergyKcal: activeEnergyKcal,
                restingEnergyKcal: restingEnergyKcal,
                exerciseMinutes: exerciseMinutes,
                standHours: standHours,
                moveGoalKcal: moveGoalKcal,
                exerciseGoalMinutes: exerciseGoalMinutes,
                standGoalHours: standGoalHours,
                sleepSeconds: sleepSeconds,
                bodyWeightKg: bodyWeightKg,
                schemaVersion: schemaVersion
            )
        }
    }

    @Published private(set) var refreshToken: Int = 0
    @Published private(set) var isBackfillingHistory: Bool = false
    @Published private(set) var backfillStatusText: String = ""
    @Published private(set) var backfillProgressCompleted: Int = 0
    @Published private(set) var backfillProgressTotal: Int = 0

    private let repository: HealthKitDailyRepositoryProtocol
    private let healthKitManager: HealthKitManager
    private let dateNormalizer: HealthKitDateNormalizer
    private let defaults = UserDefaults.standard
    private var inFlightTasks: [String: Task<DailyAggregateSnapshot, Error>] = [:]

    init(
        context: ModelContext,
        repository: HealthKitDailyRepositoryProtocol,
        healthKitManager: HealthKitManager,
        dateNormalizer: HealthKitDateNormalizer
    ) {
        self.repository = repository
        self.healthKitManager = healthKitManager
        self.dateNormalizer = dateNormalizer
        super.init(context: context)
    }

    override func loadFeature() {
        guard let userId = currentUser?.id.uuidString else { return }
        Task { [weak self] in
            await self?.upgradeCachedSummariesIfNeeded(userId: userId)
        }
    }

    func dailySummary(
        for day: Date,
        userId: String,
        policy: HealthDataFetchPolicy = .refreshIfStale
    ) async throws -> HealthKitDailyAggregateData {
        let policy = resolvedPolicy(policy)
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
        let policy = resolvedPolicy(policy)
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
                exerciseMinutes: 0,
                standHours: 0,
                moveGoalKcal: 520,
                exerciseGoalMinutes: 30,
                standGoalHours: 12,
                sleepSeconds: 0,
                bodyWeightKg: 0,
                schemaVersion: HealthKitDailyAggregateData.currentSchemaVersion
            )
        }
    }

    func refreshTodayIfNeeded(userId: String) async {
        _ = try? await dailySummary(for: Date(), userId: userId, policy: .refreshIfStale)
    }

    func forceRefreshRecentData(userId: String, days: Int = 7) async {
        _ = try? await dailySummaries(
            endingOn: Date(),
            days: max(days, 1),
            userId: userId,
            policy: .forceRefresh
        )
        refreshToken &+= 1
    }

    func cachedDataBounds(userId: String) throws -> (oldest: Date?, newest: Date?) {
        let items = try repository.fetchCachedSummaries(userId: userId)
        return (items.first?.dayStart, items.last?.dayStart)
    }

    func cachedDailySummaries(userId: String) throws -> [HealthKitDailyAggregateData] {
        try repository.fetchCachedSummaries(userId: userId)
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
                exerciseMinutes: 0,
                standHours: 0,
                moveGoalKcal: 520,
                exerciseGoalMinutes: 30,
                standGoalHours: 12,
                sleepSeconds: 0,
                bodyWeightKg: 0,
                schemaVersion: HealthKitDailyAggregateData.currentSchemaVersion
            )
        }
    }

    func backfillHistoryIfNeeded(
        userId: String,
        maxYearsBack: Int = 25,
        chunkDays: Int = 180,
        emptyChunkStop: Int = 4
    ) async -> Bool {
        if isBackfillingHistory {
            return true
        }

        let calendar = Calendar.current
        let now = Date()
        let absoluteStart = calendar.date(byAdding: .year, value: -maxYearsBack, to: now) ?? now
        let bounds = try? cachedDataBounds(userId: userId)
        let initialEnd = (bounds?.oldest ?? now).addingTimeInterval(-24 * 60 * 60)

        if initialEnd <= absoluteStart {
            return true
        }

        let requestedTotalDays = max((calendar.dateComponents([.day], from: absoluteStart, to: initialEnd).day ?? 0) + 1, 1)
        isBackfillingHistory = true
        backfillStatusText = "Loading HealthKit history..."
        backfillProgressCompleted = 0
        backfillProgressTotal = max(requestedTotalDays, 1)
        defer {
            isBackfillingHistory = false
            backfillStatusText = ""
        }

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
            backfillProgressCompleted = min(processedDays, requestedTotalDays)

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
                    (summary.exerciseMinutes ?? 0) > 0 ||
                    (summary.standHours ?? 0) > 0 ||
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
            backfillProgressCompleted = min(processedDays, requestedTotalDays)
            guard let nextEnd = calendar.date(byAdding: .day, value: -requestDays, to: cursorEnd) else {
                break
            }
            cursorEnd = nextEnd
        }

        backfillStatusText = "Loading HealthKit history... 100%"
        backfillProgressCompleted = requestedTotalDays
        if wroteAnyData {
            refreshToken &+= 1
        }
        return true
    }

    func backfillHistoryIfNeededDaily(
        userId: String,
        maxYearsBack: Int = 25,
        chunkDays: Int = 180,
        emptyChunkStop: Int = 4
    ) async -> Bool {
        let key = "gymtracker.hk.backfill.last-at.\(userId.lowercased())"
        if let lastRunAt = defaults.object(forKey: key) as? Date {
            let age = Date().timeIntervalSince(lastRunAt)
            if age < 24 * 60 * 60 {
                return true
            }
        }

        let result = await backfillHistoryIfNeeded(
            userId: userId,
            maxYearsBack: maxYearsBack,
            chunkDays: chunkDays,
            emptyChunkStop: emptyChunkStop
        )
        if result {
            defaults.set(Date(), forKey: key)
        }
        return result
    }

    func invalidateDay(for day: Date, userId: String) throws {
        let dayKey = dateNormalizer.dayKey(day)
        guard let cached = try fetchCachedSummary(userId: userId, dayKey: dayKey) else { return }
        cached.lastRefreshedAt = .distantPast
        cached.isToday = dateNormalizer.sameDay(cached.dayStart, Date())
        cached.updatedAt = Date()
        try repository.saveChanges()
        refreshToken &+= 1
    }

    func invalidateAll(userId: String) throws {
        let cachedItems = try repository.fetchCachedSummaries(userId: userId)
        for item in cachedItems {
            item.lastRefreshedAt = .distantPast
            item.isToday = dateNormalizer.sameDay(item.dayStart, Date())
            item.updatedAt = Date()
        }
        try repository.saveChanges()
    }

    func notifyExternalSummaryImport() {
        refreshToken &+= 1
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
                        exerciseMinutes: 0,
                        standHours: 0,
                        moveGoalKcal: 520,
                        exerciseGoalMinutes: 30,
                        standGoalHours: 12,
                        sleepSeconds: 0,
                        bodyWeightKg: 0,
                        schemaVersion: HealthKitDailyAggregateData.currentSchemaVersion
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
                try repository.saveChanges()
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
        try repository.fetchCachedSummary(userId: userId, dayKey: dayKey)
    }

    private func fetchCachedSummaries(
        userId: String,
        from startDay: Date,
        to endDay: Date
    ) throws -> [String: HealthKitDailyAggregateData] {
        try repository.fetchCachedSummaries(userId: userId, from: startDay, to: endDay)
    }

    private func upsertCache(with dto: HealthKitDailyAggregateData, saveImmediately: Bool = true) throws {
        let refreshedAt = Date()
        let isToday = dateNormalizer.sameDay(dto.dayStart, Date())
        try repository.upsertCache(
            with: dto,
            refreshedAt: refreshedAt,
            isToday: isToday,
            saveImmediately: saveImmediately
        )
    }

    private func mapToDTO(_ cache: HealthKitDailyAggregateData) -> HealthKitDailyAggregateData {
        cache
    }

    private func resolvedPolicy(_ policy: HealthDataFetchPolicy) -> HealthDataFetchPolicy {
        guard currentUser?.isDemo == true else { return policy }
        switch policy {
        case .cachedOnly:
            return .cachedOnly
        case .refreshIfStale, .forceRefresh:
            return .cachedOnly
        }
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

    private func upgradeCachedSummariesIfNeeded(userId: String) async {
        guard !isRunningSchemaUpgrade else { return }

        guard let cached = try? repository.fetchCachedSummaries(userId: userId), !cached.isEmpty else { return }

        let needsUpgrade = cached.contains { $0.schemaVersion < HealthKitDailyAggregateData.currentSchemaVersion }
        guard needsUpgrade else { return }

        isRunningSchemaUpgrade = true
        defer { isRunningSchemaUpgrade = false }

        let firstDay = cached.first?.dayStart ?? Date()
        let lastDay = cached.last?.dayStart ?? firstDay

        guard let fetched = try? await healthKitManager.fetchDailyAggregates(
            from: firstDay,
            to: lastDay,
            userId: userId,
            calendar: .current
        ) else {
            return
        }

        let fetchedByKey = Dictionary(uniqueKeysWithValues: fetched.map { ($0.dayKey, $0) })
        var changedAny = false

        for item in cached where item.schemaVersion < HealthKitDailyAggregateData.currentSchemaVersion {
            if let upgraded = fetchedByKey[item.dayKey] {
                item.exerciseMinutes = upgraded.exerciseMinutes
                item.standHours = upgraded.standHours
                item.moveGoalKcal = upgraded.moveGoalKcal
                item.exerciseGoalMinutes = upgraded.exerciseGoalMinutes
                item.standGoalHours = upgraded.standGoalHours
                item.bodyWeightKg = upgraded.bodyWeightKg
                item.schemaVersion = HealthKitDailyAggregateData.currentSchemaVersion
                item.updatedAt = Date()
                changedAny = true
            }
        }

        if changedAny {
            try? repository.saveChanges()
            refreshToken &+= 1
        }
    }
}
