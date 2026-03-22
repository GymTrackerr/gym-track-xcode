import Foundation

enum HealthHistoryMetric: String, CaseIterable, Identifiable {
    case steps
    case sleepHours
    case activeEnergy
    case restingEnergy
    case totalUsedCalories

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steps: return "Steps"
        case .sleepHours: return "Sleep"
        case .activeEnergy: return "Active"
        case .restingEnergy: return "Resting"
        case .totalUsedCalories: return "Used"
        }
    }
}

enum HealthHistoryChartSupport {
    static func pointsLoader(
        store: HealthKitDailyStore,
        userIdProvider: @escaping () -> String?,
        metricProvider: @escaping () -> HealthHistoryMetric
    ) -> HistoryChartPointsLoader {
        return { interval, timeframe in
            guard let userId = userIdProvider() else {
                return HistoryChartCalculator.bucketIntervals(interval: interval, timeframe: timeframe).map {
                    HistoryChartPoint(startDate: $0.start, endDate: $0.end, value: 0)
                }
            }

            let summaries = try await store.dailySummaries(in: interval, userId: userId, policy: .refreshIfStale)
            return HistoryChartCalculator.bucketIntervals(interval: interval, timeframe: timeframe).map { bucket in
                let value = summaries
                    .filter { $0.dayStart >= bucket.start && $0.dayStart < bucket.end }
                    .reduce(0.0) { partial, summary in
                        partial + metricValue(for: summary, metric: metricProvider())
                    }

                return HistoryChartPoint(startDate: bucket.start, endDate: bucket.end, value: value)
            }
        }
    }

    private static func metricValue(
        for summary: HealthKitDailyAggregateData,
        metric: HealthHistoryMetric
    ) -> Double {
        switch metric {
        case .steps:
            return summary.steps
        case .sleepHours:
            return summary.sleepSeconds / 3600
        case .activeEnergy:
            return summary.activeEnergyKcal
        case .restingEnergy:
            return summary.restingEnergyKcal
        case .totalUsedCalories:
            return summary.activeEnergyKcal + summary.restingEnergyKcal
        }
    }
}
