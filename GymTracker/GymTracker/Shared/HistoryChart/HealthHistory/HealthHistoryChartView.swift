import SwiftUI

struct HealthHistoryChartView: View {
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var healthKitDailyStore: HealthKitDailyStore

    @State private var selectedMetric: HealthHistoryMetric = .steps
    @State private var aggregationMode: HealthHistoryAggregationMode = .total

    var body: some View {
        HistoryChartView(
            navigationTitle: "Health History",
            filterStateToken: filterStateToken,
            chartStyle: selectedMetric == .weight ? .line : .bar,
            treatZeroAsMissingInLineStyles: selectedMetric == .weight,
            filterControls: {
                VStack(alignment: .leading, spacing: 10) {
                    metricPicker
                    aggregationPicker
                }
            },
            pointsProvider: { interval, timeframe in
                let metric = selectedMetric
                let mode = aggregationMode
                let provider = HealthHistoryChartSupport.pointsProvider(
                    store: healthKitDailyStore,
                    userIdProvider: { userService.currentUser?.id.uuidString },
                    metricProvider: { metric },
                    aggregationModeProvider: { mode }
                )
                return provider(interval, timeframe)
            },
            loadIntervalProvider: { interval, timeframe in
                HistoryChartLoadSupport.bufferedInterval(for: interval, timeframe: timeframe)
            },
            dataBoundsProvider: {
                self.getDataBounds()
            },
            summaryProvider: { selectedPoint, currentWindowAverage, _ in
                let value = selectedPoint?.value ?? currentWindowAverage
                return HistoryChartSummary(
                    title: selectedPoint == nil ? summaryTitle : "SELECTED",
                    valueText: valueText(for: value, metric: selectedMetric),
                    unitText: unitText(for: selectedMetric)
                )
            },
            emptyStateTextProvider: { _ in
                "No \(selectedMetric.title.lowercased()) data in this timeframe."
            }
        )
        .safeAreaInset(edge: .bottom) {
            if healthKitDailyStore.isBackfillingHistory {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(healthKitDailyStore.backfillStatusText.isEmpty ? "Loading HealthKit history..." : healthKitDailyStore.backfillStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    private func getDataBounds() -> (oldest: Date?, newest: Date?) {
        guard let userId = userService.currentUser?.id.uuidString else { return (nil, nil) }
        
        do {
            let all = try healthKitDailyStore.cachedDailySummaries(userId: userId)
            let filtered = all.filter {
                HealthHistoryChartSupport.metricValue(for: $0, metric: selectedMetric) > 0
            }
            guard !filtered.isEmpty else { return (nil, nil) }

            let oldest = filtered.min(by: { $0.dayStart < $1.dayStart })?.dayStart
            let newest = filtered.max(by: { $0.dayStart < $1.dayStart })?.dayStart
            return (oldest, newest)
        } catch {
            return (nil, nil)
        }
    }

    private var metricPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HealthHistoryMetric.allCases) { metric in
                    HistoryChartChip(title: metric.title, isSelected: selectedMetric == metric) {
                        selectedMetric = metric
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .overlay(HistoryChartHorizontalScrollHints())
    }

    private var aggregationPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HealthHistoryAggregationMode.allCases) { mode in
                    HistoryChartChip(title: mode.title, isSelected: aggregationMode == mode) {
                        aggregationMode = mode
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .overlay(HistoryChartHorizontalScrollHints())
    }

    private var summaryTitle: String {
        switch aggregationMode {
        case .total:
            return "AVG \(selectedMetric.title.uppercased())"
        case .averagePerDay:
            return "AVG \(selectedMetric.title.uppercased()) / DAY"
        }
    }

    private func valueText(for value: Double, metric: HealthHistoryMetric) -> String {
        switch metric {
        case .steps:
            return String(Int(value.rounded()))
        case .sleepHours:
            return String(format: "%.1f", value)
        case .weight:
            return String(format: "%.1f", value)
        case .activeEnergy, .restingEnergy, .totalUsedCalories:
            return String(Int(value.rounded()))
        }
    }

    private func unitText(for metric: HealthHistoryMetric) -> String? {
        let suffix = aggregationMode == .averagePerDay ? "/day" : ""
        switch metric {
        case .steps:
            return "steps\(suffix)"
        case .sleepHours:
            return "hrs\(suffix)"
        case .weight:
            return "kg\(suffix)"
        case .activeEnergy, .restingEnergy, .totalUsedCalories:
            return "kcal\(suffix)"
        }
    }

    private var filterStateToken: Int {
        var hasher = Hasher()
        hasher.combine(selectedMetric.rawValue)
        hasher.combine(aggregationMode.rawValue)
        hasher.combine(userService.currentUser?.id.uuidString ?? "no-user")
        hasher.combine(healthKitDailyStore.refreshToken)
        return hasher.finalize()
    }
}
