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

    static func nutritionPoints(
        logs: [NutritionLogEntry],
        interval: DateInterval,
        timeframe: HistoryChartTimeframe,
        metric: NutritionHistoryMetric,
        calendar: Calendar = .current
    ) -> [HistoryChartPoint] {
        HistoryChartCalculator.bucketIntervals(interval: interval, timeframe: timeframe, calendar: calendar).map { bucket in
            let value = logs
                .filter { $0.timestamp >= bucket.start && $0.timestamp < bucket.end }
                .reduce(0.0) { partial, log in
                    partial + metricValue(for: log, metric: metric)
                }

            return HistoryChartPoint(startDate: bucket.start, endDate: bucket.end, value: value)
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
        HistoryChartCalculator.bucketIntervals(interval: interval, timeframe: timeframe, calendar: calendar).map { bucket in
            let bucketLogs = logs.filter { $0.timestamp >= bucket.start && $0.timestamp < bucket.end }
            let bucketHealth = healthSummaries.filter { $0.dayStart >= bucket.start && $0.dayStart < bucket.end }

            var dayStartsWithData = Set<Date>()
            for log in bucketLogs {
                dayStartsWithData.insert(calendar.startOfDay(for: log.timestamp))
            }
            for summary in bucketHealth {
                dayStartsWithData.insert(calendar.startOfDay(for: summary.dayStart))
            }

            let eaten = bucketLogs.reduce(0.0) { $0 + $1.caloriesSnapshot }
            let resting = bucketHealth.reduce(0.0) { $0 + $1.restingEnergyKcal }
            let active = bucketHealth.reduce(0.0) { $0 + $1.activeEnergyKcal }
            let used = resting + active
            let balance = eaten - used

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
            let surplusDeficitValue = nutritionDays.reduce(0.0) { partial, day in
                let dayEaten = eatenByDay[day, default: 0]
                let dayUsed = usedByDay[day, default: 0]
                return partial + abs(dayEaten - dayUsed)
            }
            let netNutritionDayBalance = nutritionDays.reduce(0.0) { partial, day in
                let dayEaten = eatenByDay[day, default: 0]
                let dayUsed = usedByDay[day, default: 0]
                return partial + (dayEaten - dayUsed)
            }

            var segments: [HistoryChartBarSegment] = []
            let value: Double
            let dayCountForAverage: Int

            switch displayFilter {
            case .summary:
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
                value = resting + active + eaten
                dayCountForAverage = dayStartsWithData.count

            case .surplusDeficit:
                if netNutritionDayBalance != 0 {
                    segments.append(
                        HistoryChartBarSegment(
                            key: balanceSegmentKey,
                            value: surplusDeficitValue,
                            style: netNutritionDayBalance >= 0 ? .positive : .negative,
                            label: netNutritionDayBalance >= 0 ? "Surplus" : "Deficit"
                        )
                    )
                }
                value = surplusDeficitValue
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
                dayCountForAverage = dayStartsWithData.count

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
                dayCountForAverage = dayStartsWithData.count

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
                dayCountForAverage = dayStartsWithData.count
            }

            return HistoryChartPoint(
                startDate: bucket.start,
                endDate: bucket.end,
                value: value,
                segments: segments,
                summaryAverageNumerator: value,
                summaryAverageDenominator: dayCountForAverage > 0 ? Double(dayCountForAverage) : 0
            )
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
