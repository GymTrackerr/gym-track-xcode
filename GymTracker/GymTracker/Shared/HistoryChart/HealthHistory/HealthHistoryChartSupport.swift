import Foundation

enum HealthHistoryMetric: String, CaseIterable, Identifiable {
    case steps
    case sleepHours
    case activeEnergy
    case restingEnergy
    case totalUsedCalories
    case weight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steps: return "Steps"
        case .sleepHours: return "Sleep"
        case .activeEnergy: return "Active"
        case .restingEnergy: return "Resting"
        case .totalUsedCalories: return "Used"
        case .weight: return "Weight"
        }
    }
}

enum HealthHistoryAggregationMode: String, CaseIterable, Identifiable {
    case total
    case averagePerDay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .total:
            return "Total"
        case .averagePerDay:
            return "Average/Day"
        }
    }
}

enum HealthHistoryChartSupport {
    static func pointsProvider(
        store: HealthKitDailyStore,
        userIdProvider: @escaping () -> String?,
        metricProvider: @escaping () -> HealthHistoryMetric,
        aggregationModeProvider: @escaping () -> HealthHistoryAggregationMode
    ) -> (DateInterval, HistoryChartTimeframe) -> [HistoryChartPoint] {
        return { interval, timeframe in
            guard interval.end > interval.start else {
                return []
            }

            guard let userId = userIdProvider() else {
                return []
            }

            let metric = metricProvider()
            let aggregationMode = aggregationModeProvider()
            let summaries = (try? store.cachedDailySummaries(in: interval, userId: userId)) ?? []
            return points(
                from: summaries,
                interval: interval,
                timeframe: timeframe,
                metric: metric,
                aggregationMode: aggregationMode
            )
        }
    }

    static func points(
        from summaries: [HealthKitDailyAggregateData],
        interval: DateInterval,
        timeframe: HistoryChartTimeframe,
        metric: HealthHistoryMetric,
        aggregationMode: HealthHistoryAggregationMode,
        calendar: Calendar = .current
    ) -> [HistoryChartPoint] {
        guard !summaries.isEmpty, interval.end > interval.start else { return [] }

        let buckets = HistoryChartCalculator.bucketIntervals(interval: interval, timeframe: timeframe)
        
        return buckets.compactMap { bucket in
            let bucketSummaries = summaries.filter { $0.dayStart >= bucket.start && $0.dayStart < bucket.end }

            if metric == .weight {
                let weightSamples = bucketSummaries
                    .compactMap { $0.bodyWeightKg }
                    .filter { $0 > 0 && $0.isFinite }
                guard !weightSamples.isEmpty else { 
                    return nil
                }

                let total = weightSamples.reduce(0, +)
                let count = weightSamples.count
                let average = total / Double(count)

                return HistoryChartPoint(
                    startDate: bucket.start,
                    endDate: bucket.end,
                    value: average,
                    summaryAverageNumerator: total,
                    summaryAverageDenominator: Double(count)
                )
            }

            let total = bucketSummaries.reduce(0.0) { $0 + metricValue(for: $1, metric: metric) }
            
            let value: Double
            switch aggregationMode {
            case .total:
                value = total
            case .averagePerDay:
                let dayCount = calendar.dateComponents([.day], from: bucket.start, to: bucket.end).day ?? 1
                value = total / Double(dayCount)
            }
            
            return HistoryChartPoint(startDate: bucket.start, endDate: bucket.end, value: value)
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
        case .weight:
            return summary.bodyWeightKg ?? 0
        }
    }
}
