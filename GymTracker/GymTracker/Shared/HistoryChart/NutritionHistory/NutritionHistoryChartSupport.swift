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

enum NutritionChartCalculator {
    static let restingSegmentKey = "resting"
    static let activeSegmentKey = "active"
    static let eatenSegmentKey = "eaten"

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
        calendar: Calendar = .current
    ) -> [HistoryChartPoint] {
        HistoryChartCalculator.bucketIntervals(interval: interval, timeframe: timeframe, calendar: calendar).map { bucket in
            let bucketLogs = logs.filter { $0.timestamp >= bucket.start && $0.timestamp < bucket.end }
            let bucketHealth = healthSummaries.filter { $0.dayStart >= bucket.start && $0.dayStart < bucket.end }

            let eaten = bucketLogs.reduce(0.0) { $0 + $1.caloriesSnapshot }
            let resting = bucketHealth.reduce(0.0) { $0 + $1.restingEnergyKcal }
            let active = bucketHealth.reduce(0.0) { $0 + $1.activeEnergyKcal }

            var segments: [HistoryChartBarSegment] = []
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
                        label: "Eaten"
                    )
                )
            }

            let total = resting + active + eaten
            return HistoryChartPoint(
                startDate: bucket.start,
                endDate: bucket.end,
                value: total,
                segments: segments
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
