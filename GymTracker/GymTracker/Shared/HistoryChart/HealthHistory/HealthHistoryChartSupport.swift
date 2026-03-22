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
    static func pointsProvider(
        store: HealthKitDailyStore,
        userIdProvider: @escaping () -> String?,
        metricProvider: @escaping () -> HealthHistoryMetric
    ) -> (DateInterval, HistoryChartTimeframe) -> [HistoryChartPoint] {
        return { interval, timeframe in
            guard interval.end > interval.start else {
                return []
            }
            let calendar = Calendar.current
            let now = Date()
            let maximumAllowed = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            let clampedStartDate = interval.start
            let clampedEndDate = min(interval.end, maximumAllowed)
            guard clampedEndDate > clampedStartDate else {
                return []
            }

            let dayStart = calendar.startOfDay(for: clampedStartDate)
            let dayEndBase = clampedEndDate > clampedStartDate ? clampedEndDate.addingTimeInterval(-1) : clampedEndDate
            let dayEnd = calendar.startOfDay(for: dayEndBase)
            let normalizedEnd = calendar.date(byAdding: .day, value: 1, to: dayEnd) ?? dayEnd
            let normalizedInterval = DateInterval(start: dayStart, end: normalizedEnd)

            guard let userId = userIdProvider() else {
                return HistoryChartCalculator.bucketIntervals(interval: interval, timeframe: timeframe).map {
                    HistoryChartPoint(startDate: $0.start, endDate: $0.end, value: 0)
                }
            }

            let metric = metricProvider()
            let summaries = (try? store.cachedDailySummaries(in: normalizedInterval, userId: userId)) ?? []
            let points = HistoryChartCalculator.bucketIntervals(interval: interval, timeframe: timeframe).map { bucket in
                let value = summaries
                    .filter { $0.dayStart >= bucket.start && $0.dayStart < bucket.end }
                    .reduce(0.0) { partial, summary in
                        partial + metricValue(for: summary, metric: metric)
                    }

                return HistoryChartPoint(startDate: bucket.start, endDate: bucket.end, value: value)
            }
            return points
        }
    }

    static func metricValue(
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
