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
                    let health = (try? healthKitDailyStore.cachedDailySummaries(in: interval, userId: userId)) ?? []
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
            dataBoundsProvider: {
                if selectedMetric == .energyBalance {
                    return energyBalanceBounds()
                }
                return (try? nutritionService.nutritionBounds(for: selectedMetric.seriesMetric)) ?? (nil, nil)
            },
            summaryProvider: { selectedPoint, currentWindowAverage, _ in
                if selectedMetric == .energyBalance {
                    return energyBalanceSummary(
                        selectedPoint: selectedPoint,
                        currentWindowAverage: currentWindowAverage,
                        filter: selectedEnergyFilter
                    )
                }
                let value = selectedPoint?.value ?? currentWindowAverage
                return HistoryChartSummary(
                    title: selectedPoint == nil ? "AVG \(selectedMetric.title.uppercased())" : "SELECTED",
                    valueText: valueText(for: value),
                    unitText: selectedMetric.unitLabel
                )
            },
            summaryDetailsProvider: { selectedPoint, _, _ in
                energySummaryDetails(for: selectedPoint, filter: selectedEnergyFilter)
            },
            emptyStateTextProvider: { _ in
                "No \(selectedMetric.title.lowercased()) data in this timeframe."
            }
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
        let rawNutritionBounds = (try? nutritionService.nutritionBounds(for: .calories)) ?? (nil, nil)
        let nutritionBounds: (oldest: Date?, newest: Date?) = (rawNutritionBounds.0, rawNutritionBounds.1)

        if selectedEnergyFilter == .surplusDeficit {
            return nutritionBounds
        }

        guard let userId = userService.currentUser?.id.uuidString else {
            return nutritionBounds
        }

        let health = (try? healthKitDailyStore.cachedDailySummaries(userId: userId)) ?? []
        let energyHealth = health.filter { ($0.activeEnergyKcal + $0.restingEnergyKcal) > 0 }
        let healthOldest = energyHealth.min(by: { $0.dayStart < $1.dayStart })?.dayStart
        let healthNewest = energyHealth.max(by: { $0.dayStart < $1.dayStart })?.dayStart

        return (
            oldest: minDate(nutritionBounds.oldest, healthOldest),
            newest: maxDate(nutritionBounds.newest, healthNewest)
        )
    }

    private func energyBalanceSummary(
        selectedPoint: HistoryChartPoint?,
        currentWindowAverage: Double,
        filter: NutritionEnergySecondaryFilter
    ) -> HistoryChartSummary {
        guard let selectedPoint else {
            let title: String
            switch filter {
            case .summary:
                title = "AVG DAILY ENERGY"
            case .surplusDeficit:
                title = "AVG DAILY DEFICIT"
            case .active:
                title = "AVG DAILY ACTIVE"
            case .resting:
                title = "AVG DAILY RESTING"
            case .nutrition:
                title = "AVG DAILY NUTRITION"
            }
            return HistoryChartSummary(
                title: title,
                valueText: String(Int(currentWindowAverage.rounded())),
                unitText: "kcal"
            )
        }

        let resting = selectedPoint.segmentValue(for: NutritionChartCalculator.restingSegmentKey) ?? 0
        let active = selectedPoint.segmentValue(for: NutritionChartCalculator.activeSegmentKey) ?? 0
        let eaten = selectedPoint.segmentValue(for: NutritionChartCalculator.eatenSegmentKey) ?? 0
        let balance = eaten - (resting + active)

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
                valueText: String(Int(selectedValue.rounded())),
                unitText: "kcal"
            )
        }
    }

    private func energySummaryDetails(
        for selectedPoint: HistoryChartPoint?,
        filter: NutritionEnergySecondaryFilter
    ) -> [HistoryChartSummaryDetail] {
        guard selectedMetric == .energyBalance, let selectedPoint else {
            return []
        }

        let resting = selectedPoint.segmentValue(for: NutritionChartCalculator.restingSegmentKey) ?? 0
        let active = selectedPoint.segmentValue(for: NutritionChartCalculator.activeSegmentKey) ?? 0
        let eaten = selectedPoint.segmentValue(for: NutritionChartCalculator.eatenSegmentKey) ?? 0
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
            let details = surplusDeficitDetails(for: selectedPoint)
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
        for point: HistoryChartPoint
    ) -> (used: Double, eaten: Double, balanceValue: Double, title: String)? {
        guard let userId = userService.currentUser?.id.uuidString else {
            return nil
        }

        let interval = DateInterval(start: point.startDate, end: point.endDate)
        let logs = (try? nutritionService.logsInDateInterval(interval)) ?? []
        let health = (try? healthKitDailyStore.cachedDailySummaries(in: interval, userId: userId)) ?? []

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

        return (used: used, eaten: eaten, balanceValue: balanceValue, title: netBalance >= 0 ? "Surplus" : "Deficit")
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
