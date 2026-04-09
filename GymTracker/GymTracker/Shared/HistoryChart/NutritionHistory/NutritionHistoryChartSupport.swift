import Foundation

enum NutritionHistoryMetric: String, CaseIterable, Identifiable {
    case calories
    case protein
    case carbs
    case fat
    case energyBalance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calories:
            return "Calories"
        case .protein:
            return "Protein"
        case .carbs:
            return "Carbs"
        case .fat:
            return "Fat"
        case .energyBalance:
            return "Energy"
        }
    }

    var unitLabel: String {
        switch self {
        case .calories:
            return "kcal"
        case .protein, .carbs, .fat:
            return "g"
        case .energyBalance:
            return "kcal"
        }
    }

    var seriesMetric: NutritionService.NutritionSeriesMetric {
        switch self {
        case .calories:
            return .calories
        case .protein:
            return .protein
        case .carbs:
            return .carbs
        case .fat:
            return .fat
        case .energyBalance:
            return .calories
        }
    }
}

enum NutritionEnergySecondaryFilter: String, CaseIterable, Identifiable {
    case summary
    case surplusDeficit
    case active
    case resting
    case nutrition

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summary:
            return "Summary"
        case .surplusDeficit:
            return "Surplus/Deficit"
        case .active:
            return "Active"
        case .resting:
            return "Resting"
        case .nutrition:
            return "Nutrition"
        }
    }
}

enum NutritionChartCalculator {
    static let restingSegmentKey = "resting"
    static let activeSegmentKey = "active"
    static let eatenSegmentKey = "eaten"
    static let balanceSegmentKey = "balance"
    static let restingDeficitSegmentKey = "restingDeficit"
    static let activeDeficitSegmentKey = "activeDeficit"
    static let surplusSegmentKey = "surplus"

    static func nutritionPoints(
        logs: [NutritionLogEntry],
        interval: DateInterval,
        timeframe: HistoryChartTimeframe,
        metric: NutritionHistoryMetric,
        calendar: Calendar = .current
    ) -> [HistoryChartPoint] {
        let shouldAverage = shouldAverageBuckets(for: timeframe)
        return HistoryChartCalculator.bucketIntervals(interval: interval, timeframe: timeframe, calendar: calendar).map { bucket in
            let bucketLogs = logs.filter { $0.timestamp >= bucket.start && $0.timestamp < bucket.end }
            let totalValue = bucketLogs.reduce(0.0) { partial, log in
                partial + metricValue(for: log, metric: metric)
            }
            let dayCount = Set(bucketLogs.map { calendar.startOfDay(for: $0.timestamp) }).count
            let displayedValue: Double
            if shouldAverage, dayCount > 0 {
                displayedValue = totalValue / Double(dayCount)
            } else {
                displayedValue = totalValue
            }

            return HistoryChartPoint(
                startDate: bucket.start,
                endDate: bucket.end,
                value: displayedValue,
                summaryAverageNumerator: totalValue,
                summaryAverageDenominator: dayCount > 0 ? Double(dayCount) : 0
            )
        }
    }

    static func energyBalancePoints(
        logs: [NutritionLogEntry],
        healthSummaries: [HealthKitDailyAggregateData],
        interval: DateInterval,
        timeframe: HistoryChartTimeframe,
        displayFilter: NutritionEnergySecondaryFilter,
        calendar: Calendar = .current
    ) -> [HistoryChartPoint] {
        let shouldAverage = shouldAverageBuckets(for: timeframe)
        return HistoryChartCalculator.bucketIntervals(interval: interval, timeframe: timeframe, calendar: calendar).map { bucket in
            let bucketLogs = logs.filter { $0.timestamp >= bucket.start && $0.timestamp < bucket.end }
            let bucketHealth = healthSummaries.filter { $0.dayStart >= bucket.start && $0.dayStart < bucket.end }

            let nutritionDaysSet = Set(bucketLogs.map { calendar.startOfDay(for: $0.timestamp) })
            let healthDaysSet = Set(bucketHealth.map { calendar.startOfDay(for: $0.dayStart) })
            var dayStartsWithData = Set<Date>()
            for day in nutritionDaysSet {
                dayStartsWithData.insert(day)
            }
            for summary in bucketHealth {
                dayStartsWithData.insert(calendar.startOfDay(for: summary.dayStart))
            }

            let eaten = bucketLogs.reduce(0.0) { $0 + $1.caloriesSnapshot }
            let resting = bucketHealth.reduce(0.0) { $0 + $1.restingEnergyKcal }
            let active = bucketHealth.reduce(0.0) { $0 + $1.activeEnergyKcal }
            var eatenByDay: [Date: Double] = [:]
            for log in bucketLogs {
                let day = calendar.startOfDay(for: log.timestamp)
                eatenByDay[day, default: 0] += log.caloriesSnapshot
            }

            var usedByDay: [Date: Double] = [:]
            for summary in bucketHealth {
                let day = calendar.startOfDay(for: summary.dayStart)
                usedByDay[day, default: 0] += summary.restingEnergyKcal + summary.activeEnergyKcal
            }

            let nutritionDays = Array(eatenByDay.keys)
            let signedDeficitValue = nutritionDays.reduce(0.0) { partial, day in
                let dayEaten = eatenByDay[day, default: 0]
                let dayUsed = usedByDay[day, default: 0]
                // Signed deficit: positive means deficit, negative means surplus.
                return partial + (dayUsed - dayEaten)
            }

            var segments: [HistoryChartBarSegment] = []
            let value: Double
            let dayCountForAverage: Int

            switch displayFilter {
            case .summary:
                let hasNutritionData = !nutritionDays.isEmpty
                let restingForSummary: Double
                let activeForSummary: Double
                if hasNutritionData {
                    restingForSummary = nutritionDaysSet.reduce(0.0) { partial, day in
                        partial + bucketHealth
                            .filter { calendar.startOfDay(for: $0.dayStart) == day }
                            .reduce(0.0) { $0 + $1.restingEnergyKcal }
                    }
                    activeForSummary = nutritionDaysSet.reduce(0.0) { partial, day in
                        partial + bucketHealth
                            .filter { calendar.startOfDay(for: $0.dayStart) == day }
                            .reduce(0.0) { $0 + $1.activeEnergyKcal }
                    }
                } else {
                    restingForSummary = resting
                    activeForSummary = active
                }

                let used = restingForSummary + activeForSummary
                let deficit = hasNutritionData ? max(used - eaten, 0) : 0
                let surplus = hasNutritionData ? max(eaten - used, 0) : 0

                let activeDeficit = min(deficit, activeForSummary)
                let restingDeficit = min(max(deficit - activeForSummary, 0), restingForSummary)
                let remainingActive = max(activeForSummary - activeDeficit, 0)
                let remainingResting = max(restingForSummary - restingDeficit, 0)

                if remainingResting > 0 {
                    segments.append(
                        HistoryChartBarSegment(
                            key: restingSegmentKey,
                            value: remainingResting,
                            style: .secondary,
                            label: "Resting"
                        )
                    )
                }
                if restingDeficit > 0 {
                    segments.append(
                        HistoryChartBarSegment(
                            key: restingDeficitSegmentKey,
                            value: restingDeficit,
                            style: .negativeSecondary,
                            label: "Deficit (Resting)"
                        )
                    )
                }
                if remainingActive > 0 {
                    segments.append(
                        HistoryChartBarSegment(
                            key: activeSegmentKey,
                            value: remainingActive,
                            style: .primary,
                            label: "Active"
                        )
                    )
                }
                if activeDeficit > 0 {
                    segments.append(
                        HistoryChartBarSegment(
                            key: activeDeficitSegmentKey,
                            value: activeDeficit,
                            style: .negative,
                            label: "Deficit (Active)"
                        )
                    )
                }
                if surplus > 0 {
                    segments.append(
                        HistoryChartBarSegment(
                            key: surplusSegmentKey,
                            value: surplus,
                            style: .positive,
                            label: "Surplus"
                        )
                    )
                }
                value = used + surplus
                dayCountForAverage = hasNutritionData ? nutritionDaysSet.count : healthDaysSet.count

            case .surplusDeficit:
                if signedDeficitValue != 0 {
                    segments.append(
                        HistoryChartBarSegment(
                            key: balanceSegmentKey,
                            value: signedDeficitValue,
                            style: signedDeficitValue >= 0 ? .negative : .positive,
                            label: signedDeficitValue >= 0 ? "Deficit" : "Surplus"
                        )
                    )
                }
                value = signedDeficitValue
                dayCountForAverage = nutritionDays.count

            case .active:
                if active > 0 {
                    segments.append(
                        HistoryChartBarSegment(
                            key: activeSegmentKey,
                            value: active,
                            style: .primary,
                            label: "Active"
                        )
                    )
                }
                value = active
                dayCountForAverage = healthDaysSet.count

            case .resting:
                if resting > 0 {
                    segments.append(
                        HistoryChartBarSegment(
                            key: restingSegmentKey,
                            value: resting,
                            style: .secondary,
                            label: "Resting"
                        )
                    )
                }
                value = resting
                dayCountForAverage = healthDaysSet.count

            case .nutrition:
                if eaten > 0 {
                    segments.append(
                        HistoryChartBarSegment(
                            key: eatenSegmentKey,
                            value: eaten,
                            style: .positive,
                            label: "Nutrition"
                        )
                    )
                }
                value = eaten
                dayCountForAverage = nutritionDaysSet.count
            }

            let normalizedValue: Double
            let normalizedSegments: [HistoryChartBarSegment]
            if shouldAverage, dayCountForAverage > 0 {
                let divisor = Double(dayCountForAverage)
                normalizedValue = value / divisor
                normalizedSegments = segments.map { segment in
                    HistoryChartBarSegment(
                        key: segment.key,
                        value: segment.value / divisor,
                        style: segment.style,
                        label: segment.label
                    )
                }
            } else {
                normalizedValue = value
                normalizedSegments = segments
            }

            return HistoryChartPoint(
                startDate: bucket.start,
                endDate: bucket.end,
                value: normalizedValue,
                segments: normalizedSegments,
                summaryAverageNumerator: value,
                summaryAverageDenominator: dayCountForAverage > 0 ? Double(dayCountForAverage) : 0
            )
        }
    }

    private static func shouldAverageBuckets(for timeframe: HistoryChartTimeframe) -> Bool {
        switch timeframe {
        case .sixMonths, .year, .fiveYears:
            return true
        case .week, .month:
            return false
        }
    }

    private static func metricValue(for log: NutritionLogEntry, metric: NutritionHistoryMetric) -> Double {
        switch metric {
        case .calories:
            return log.caloriesSnapshot
        case .protein:
            return log.proteinSnapshot
        case .carbs:
            return log.carbsSnapshot
        case .fat:
            return log.fatSnapshot
        case .energyBalance:
            return 0.0
        }
    }
}
