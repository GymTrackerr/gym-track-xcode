import SwiftUI

struct HealthHistoryChartView: View {
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var healthKitDailyStore: HealthKitDailyStore

    @State private var selectedMetric: HealthHistoryMetric = .steps

    var body: some View {
        HistoryChartView(
            navigationTitle: "Health History",
            filterStateToken: filterStateToken,
            filterControls: {
                metricPicker
            },
            pointsProvider: { interval, timeframe in
                let metric = selectedMetric
                let provider = HealthHistoryChartSupport.pointsProvider(
                    store: healthKitDailyStore,
                    userIdProvider: { userService.currentUser?.id.uuidString },
                    metricProvider: { metric }
                )
                return provider(interval, timeframe)
            },
            loadIntervalProvider: { interval, timeframe in
                HistoryChartLoadSupport.bufferedInterval(for: interval, timeframe: timeframe)
            },
            dataBoundsProvider: {
                guard let userId = userService.currentUser?.id.uuidString else { return (nil, nil) }
                let summaries = (try? healthKitDailyStore.cachedDailySummaries(userId: userId)) ?? []
                let filtered = summaries.filter {
                    HealthHistoryChartSupport.metricValue(for: $0, metric: selectedMetric) > 0
                }
                let oldest = filtered.min(by: { $0.dayStart < $1.dayStart })?.dayStart
                let newest = filtered.max(by: { $0.dayStart < $1.dayStart })?.dayStart
                return (oldest, newest)
            },
            summaryProvider: { selectedPoint, currentWindowAverage, _ in
                let value = selectedPoint?.value ?? currentWindowAverage
                return HistoryChartSummary(
                    title: selectedPoint == nil ? "AVG \(selectedMetric.title.uppercased())" : "SELECTED",
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

    private func valueText(for value: Double, metric: HealthHistoryMetric) -> String {
        switch metric {
        case .steps:
            return String(Int(value.rounded()))
        case .sleepHours:
            return String(format: "%.1f", value)
        case .activeEnergy, .restingEnergy, .totalUsedCalories:
            return String(Int(value.rounded()))
        }
    }

    private func unitText(for metric: HealthHistoryMetric) -> String? {
        switch metric {
        case .steps:
            return "steps"
        case .sleepHours:
            return "hrs"
        case .activeEnergy, .restingEnergy, .totalUsedCalories:
            return "kcal"
        }
    }

    private var filterStateToken: Int {
        var hasher = Hasher()
        hasher.combine(selectedMetric.rawValue)
        hasher.combine(userService.currentUser?.id.uuidString ?? "no-user")
        hasher.combine(healthKitDailyStore.refreshToken)
        return hasher.finalize()
    }
}
