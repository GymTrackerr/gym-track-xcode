import Foundation

enum NutritionHistoryMetric: String, CaseIterable, Identifiable {
    case calories
    case protein
    case carbs
    case fat

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
        }
    }

    var unitLabel: String {
        switch self {
        case .calories:
            return "kcal"
        case .protein, .carbs, .fat:
            return "g"
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
        }
    }
}

enum NutritionChartCalculator {
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
        }
    }
}
