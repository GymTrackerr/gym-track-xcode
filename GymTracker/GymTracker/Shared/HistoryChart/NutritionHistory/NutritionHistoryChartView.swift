import SwiftUI

struct NutritionHistoryChartView: View {
    @EnvironmentObject var nutritionService: NutritionService
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var healthKitDailyStore: HealthKitDailyStore

    @State private var selectedMetric: NutritionHistoryMetric = .calories
    @State private var selectedEnergyFilter: NutritionEnergySecondaryFilter = .summary

    var body: some View {
        HistoryChartView(
            navigationTitle: "Nutrition History",
            filterStateToken: filterStateToken,
            filterControls: {
                VStack(alignment: .leading, spacing: 10) {
                    metricPicker
                    if selectedMetric == .energyBalance {
                        energySecondaryFilterPicker
                    }
                }
            },
            pointsProvider: { interval, timeframe in
                switch selectedMetric {
                case .energyBalance:
                    guard let userId = userService.currentUser?.id.uuidString else {
                        return []
                    }
                    let logs = (try? nutritionService.logsInDateInterval(interval)) ?? []
                    let health = (try? healthKitDailyStore.cachedExistingDailySummaries(in: interval, userId: userId)) ?? []
                    return NutritionChartCalculator.energyBalancePoints(
                        logs: logs,
                        healthSummaries: health,
                        interval: interval,
                        timeframe: timeframe,
                        displayFilter: selectedEnergyFilter
                    )
                default:
                    let logs = (try? nutritionService.logsInDateInterval(interval)) ?? []
                    return NutritionChartCalculator.nutritionPoints(
                        logs: logs,
                        interval: interval,
                        timeframe: timeframe,
                        metric: selectedMetric
                    )
                }
            },
            loadIntervalProvider: { interval, timeframe in
                HistoryChartLoadSupport.bufferedInterval(for: interval, timeframe: timeframe)
            },
            dataBoundsProvider: {
                if selectedMetric == .energyBalance {
                    return energyBalanceBounds()
                }
                return (try? nutritionService.nutritionBounds(for: selectedMetric.seriesMetric)) ?? (nil, nil)
            },
            summaryProvider: { selectedPoint, currentWindowAverage, timeframe in
                if selectedMetric == .energyBalance {
                    return energyBalanceSummary(
                        selectedPoint: selectedPoint,
                        currentWindowAverage: currentWindowAverage,
                        filter: selectedEnergyFilter,
                        timeframe: timeframe
                    )
                }
                let value = selectedPoint?.value ?? currentWindowAverage
                return HistoryChartSummary(
                    title: selectedPoint == nil ? "AVG \(selectedMetric.title.uppercased())" : "SELECTED",
                    valueText: valueText(for: value),
                    unitText: selectedMetric.unitLabel
                )
            },
            summaryDetailsProvider: { selectedPoint, _, timeframe in
                energySummaryDetails(for: selectedPoint, filter: selectedEnergyFilter, timeframe: timeframe)
            },
            emptyStateTextProvider: { _ in
                "No \(selectedMetric.title.lowercased()) data in this timeframe."
            },
            fallbackLookbackMonths: selectedMetric == .energyBalance ? 12 : nil,
            reloadToken: healthKitDailyStore.chartRefreshToken
        )
    }

    private var metricPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NutritionHistoryMetric.allCases) { metric in
                    HistoryChartChip(title: metric.title, isSelected: selectedMetric == metric) {
                        selectedMetric = metric
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .overlay(HistoryChartHorizontalScrollHints())
    }

    private var energySecondaryFilterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NutritionEnergySecondaryFilter.allCases) { filter in
                    HistoryChartChip(title: filter.title, isSelected: selectedEnergyFilter == filter) {
                        selectedEnergyFilter = filter
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .overlay(HistoryChartHorizontalScrollHints())
    }

    private func energyBalanceBounds() -> (oldest: Date?, newest: Date?) {
        let rawNutritionBounds: (Date?, Date?) = (try? nutritionService.nutritionBounds(for: .calories)) ?? (nil, nil)
        let nutritionBounds: (oldest: Date?, newest: Date?) = (rawNutritionBounds.0, rawNutritionBounds.1)

        if selectedEnergyFilter == .surplusDeficit {
            return nutritionBounds
        }

        guard let userId = userService.currentUser?.id.uuidString else {
            return nutritionBounds
        }

        let healthBounds: (oldest: Date?, newest: Date?) =
            (try? healthKitDailyStore.cachedDataBounds(userId: userId)) ?? (oldest: nil, newest: nil)

        let mergedOldest = minDate(nutritionBounds.oldest, healthBounds.oldest)
        let mergedNewest = maxDate(nutritionBounds.newest, healthBounds.newest)
        let calendar = Calendar.current
        let fallbackOldest = calendar.startOfDay(
            for: calendar.date(byAdding: .month, value: -12, to: Date()) ?? Date()
        )

        return (
            oldest: minDate(mergedOldest, fallbackOldest),
            newest: maxDate(mergedNewest, Date())
        )
    }

    private func energyBalanceSummary(
        selectedPoint: HistoryChartPoint?,
        currentWindowAverage: Double,
        filter: NutritionEnergySecondaryFilter,
        timeframe: HistoryChartTimeframe
    ) -> HistoryChartSummary {
        guard let selectedPoint else {
            let title: String
            let displayedAverage: Double
            switch filter {
            case .summary:
                title = "AVG DAILY ENERGY"
                displayedAverage = currentWindowAverage
            case .surplusDeficit:
                if currentWindowAverage > 0 {
                    title = "AVG DAILY DEFICIT"
                } else if currentWindowAverage < 0 {
                    title = "AVG DAILY SURPLUS"
                } else {
                    title = "AVG DAILY BALANCED"
                }
                displayedAverage = abs(currentWindowAverage)
            case .active:
                title = "AVG DAILY ACTIVE"
                displayedAverage = currentWindowAverage
            case .resting:
                title = "AVG DAILY RESTING"
                displayedAverage = currentWindowAverage
            case .nutrition:
                title = "AVG DAILY NUTRITION"
                displayedAverage = currentWindowAverage
            }
            return HistoryChartSummary(
                title: title,
                valueText: String(Int(displayedAverage.rounded())),
                unitText: "kcal"
            )
        }

        let totals = energyTotals(for: selectedPoint, filter: filter, timeframe: timeframe)
        let resting = totals?.resting ?? (selectedPoint.segmentValue(for: NutritionChartCalculator.restingSegmentKey) ?? 0)
        let active = totals?.active ?? (selectedPoint.segmentValue(for: NutritionChartCalculator.activeSegmentKey) ?? 0)
        let eaten = totals?.eaten ?? (selectedPoint.segmentValue(for: NutritionChartCalculator.eatenSegmentKey) ?? 0)

        switch filter {
        case .summary:
            return HistoryChartSummary(
                title: "Selected",
                valueText: String(Int(selectedPoint.plottedValue.rounded())),
                unitText: "kcal"
            )
        case .active:
            return HistoryChartSummary(
                title: "Active",
                valueText: String(Int(active.rounded())),
                unitText: "kcal"
            )
        case .resting:
            return HistoryChartSummary(
                title: "Resting",
                valueText: String(Int(resting.rounded())),
                unitText: "kcal"
            )
        case .nutrition:
            return HistoryChartSummary(
                title: "Nutrition",
                valueText: String(Int(eaten.rounded())),
                unitText: "kcal"
            )
        case .surplusDeficit:
            let balanceSegment = selectedPoint.segments.first { $0.key == NutritionChartCalculator.balanceSegmentKey }
            let title = balanceSegment?.label ?? "Balanced"
            let selectedValue = balanceSegment?.value ?? selectedPoint.value

            return HistoryChartSummary(
                title: title,
                valueText: String(Int(abs(selectedValue).rounded())),
                unitText: "kcal"
            )
        }
    }

    private func energySummaryDetails(
        for selectedPoint: HistoryChartPoint?,
        filter: NutritionEnergySecondaryFilter,
        timeframe: HistoryChartTimeframe
    ) -> [HistoryChartSummaryDetail] {
        guard selectedMetric == .energyBalance, let selectedPoint else {
            return []
        }

        let totals = energyTotals(for: selectedPoint, filter: filter, timeframe: timeframe)
        let resting = totals?.resting ?? (selectedPoint.segmentValue(for: NutritionChartCalculator.restingSegmentKey) ?? 0)
        let active = totals?.active ?? (selectedPoint.segmentValue(for: NutritionChartCalculator.activeSegmentKey) ?? 0)
        let eaten = totals?.eaten ?? (selectedPoint.segmentValue(for: NutritionChartCalculator.eatenSegmentKey) ?? 0)
        let balance = eaten - (resting + active)
        let balanceTitle = balance >= 0 ? "Surplus" : "Deficit"

        switch filter {
        case .summary:
            return [
                HistoryChartSummaryDetail(
                    title: balanceTitle,
                    valueText: String(Int(abs(balance).rounded())),
                    unitText: "kcal"
                ),
                HistoryChartSummaryDetail(
                    title: "Active",
                    valueText: String(Int(active.rounded())),
                    unitText: "kcal"
                ),
                HistoryChartSummaryDetail(
                    title: "Resting",
                    valueText: String(Int(resting.rounded())),
                    unitText: "kcal"
                ),
                HistoryChartSummaryDetail(
                    title: "Nutrition",
                    valueText: String(Int(eaten.rounded())),
                    unitText: "kcal"
                )
            ]
        case .surplusDeficit:
            let details = surplusDeficitDetails(for: selectedPoint, timeframe: timeframe)
            let used = details?.used ?? (resting + active)
            let eatenValue = details?.eaten ?? eaten
            let balanceValue = details?.balanceValue ?? abs(balance)
            let title = details?.title ?? balanceTitle
            return [
                HistoryChartSummaryDetail(
                    title: "Used",
                    valueText: String(Int(used.rounded())),
                    unitText: "kcal"
                ),
                HistoryChartSummaryDetail(
                    title: "Eaten",
                    valueText: String(Int(eatenValue.rounded())),
                    unitText: "kcal"
                ),
                HistoryChartSummaryDetail(
                    title: title,
                    valueText: String(Int(balanceValue.rounded())),
                    unitText: "kcal"
                )
            ]
        case .active, .resting, .nutrition:
            return []
        }
    }

    private func surplusDeficitDetails(
        for point: HistoryChartPoint,
        timeframe: HistoryChartTimeframe
    ) -> (used: Double, eaten: Double, balanceValue: Double, title: String)? {
        guard let userId = userService.currentUser?.id.uuidString else {
            return nil
        }

        let interval = DateInterval(start: point.startDate, end: point.endDate)
        let logs = (try? nutritionService.logsInDateInterval(interval)) ?? []
        let health = (try? healthKitDailyStore.cachedExistingDailySummaries(in: interval, userId: userId)) ?? []

        var eatenByDay: [Date: Double] = [:]
        for log in logs {
            let day = Calendar.current.startOfDay(for: log.timestamp)
            eatenByDay[day, default: 0] += log.caloriesSnapshot
        }

        guard !eatenByDay.isEmpty else {
            return nil
        }

        var usedByDay: [Date: Double] = [:]
        for summary in health {
            let day = Calendar.current.startOfDay(for: summary.dayStart)
            usedByDay[day, default: 0] += summary.restingEnergyKcal + summary.activeEnergyKcal
        }

        let nutritionDays = Array(eatenByDay.keys)
        let eaten = nutritionDays.reduce(0.0) { partial, day in
            partial + eatenByDay[day, default: 0]
        }
        let used = nutritionDays.reduce(0.0) { partial, day in
            partial + usedByDay[day, default: 0]
        }
        let balanceValue = nutritionDays.reduce(0.0) { partial, day in
            let dayEaten = eatenByDay[day, default: 0]
            let dayUsed = usedByDay[day, default: 0]
            return partial + abs(dayEaten - dayUsed)
        }
        let netBalance = nutritionDays.reduce(0.0) { partial, day in
            let dayEaten = eatenByDay[day, default: 0]
            let dayUsed = usedByDay[day, default: 0]
            return partial + (dayEaten - dayUsed)
        }

        let shouldAverage = shouldAverageBuckets(for: timeframe)
        let count = nutritionDays.count
        let normalizedUsed = shouldAverage && count > 0 ? used / Double(count) : used
        let normalizedEaten = shouldAverage && count > 0 ? eaten / Double(count) : eaten
        let normalizedBalance = shouldAverage && count > 0 ? balanceValue / Double(count) : balanceValue

        return (
            used: normalizedUsed,
            eaten: normalizedEaten,
            balanceValue: normalizedBalance,
            title: netBalance >= 0 ? "Surplus" : "Deficit"
        )
    }

    private func energyTotals(
        for point: HistoryChartPoint,
        filter: NutritionEnergySecondaryFilter,
        timeframe: HistoryChartTimeframe
    ) -> (resting: Double, active: Double, eaten: Double)? {
        guard let userId = userService.currentUser?.id.uuidString else {
            return nil
        }

        let interval = DateInterval(start: point.startDate, end: point.endDate)
        let logs = (try? nutritionService.logsInDateInterval(interval)) ?? []
        let health = (try? healthKitDailyStore.cachedExistingDailySummaries(in: interval, userId: userId)) ?? []

        let logDays = Set(logs.map { Calendar.current.startOfDay(for: $0.timestamp) })
        let healthDays = Set(health.map { Calendar.current.startOfDay(for: $0.dayStart) })
        let eatenRaw = logs.reduce(0.0) { $0 + $1.caloriesSnapshot }

        let healthForSummary: [HealthKitDailyAggregateData]
        if !logDays.isEmpty {
            healthForSummary = health.filter { logDays.contains(Calendar.current.startOfDay(for: $0.dayStart)) }
        } else {
            healthForSummary = health
        }
        let restingRaw: Double
        let activeRaw: Double
        if filter == .summary {
            restingRaw = healthForSummary.reduce(0.0) { $0 + $1.restingEnergyKcal }
            activeRaw = healthForSummary.reduce(0.0) { $0 + $1.activeEnergyKcal }
        } else {
            restingRaw = health.reduce(0.0) { $0 + $1.restingEnergyKcal }
            activeRaw = health.reduce(0.0) { $0 + $1.activeEnergyKcal }
        }

        let shouldAverage = shouldAverageBuckets(for: timeframe)
        let dayCount: Int
        switch filter {
        case .summary:
            dayCount = !logDays.isEmpty ? logDays.count : healthDays.count
        case .surplusDeficit, .nutrition:
            dayCount = logDays.count
        case .active, .resting:
            dayCount = healthDays.count
        }

        let eaten = shouldAverage && dayCount > 0 ? eatenRaw / Double(dayCount) : eatenRaw
        let resting = shouldAverage && dayCount > 0 ? restingRaw / Double(dayCount) : restingRaw
        let active = shouldAverage && dayCount > 0 ? activeRaw / Double(dayCount) : activeRaw
        return (resting: resting, active: active, eaten: eaten)
    }

    private func shouldAverageBuckets(for timeframe: HistoryChartTimeframe) -> Bool {
        switch timeframe {
        case .sixMonths, .year, .fiveYears:
            return true
        case .week, .month:
            return false
        }
    }

    private var filterStateToken: Int {
        var hasher = Hasher()
        hasher.combine(selectedMetric.rawValue)
        hasher.combine(selectedEnergyFilter.rawValue)
        hasher.combine(userService.currentUser?.id.uuidString ?? "no-user")
        return hasher.finalize()
    }

    private func minDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (l?, r?):
            return min(l, r)
        case let (l?, nil):
            return l
        case let (nil, r?):
            return r
        default:
            return nil
        }
    }

    private func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (l?, r?):
            return max(l, r)
        case let (l?, nil):
            return l
        case let (nil, r?):
            return r
        default:
            return nil
        }
    }

    private func valueText(for value: Double) -> String {
        if selectedMetric == .calories || selectedMetric == .energyBalance {
            return String(Int(value.rounded()))
        }
        return SetDisplayFormatter.formatDecimal(value)
    }

}
