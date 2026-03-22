import SwiftUI

struct HealthHistoryChartView: View {
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var healthKitDailyStore: HealthKitDailyStore

    @State private var selectedMetric: HealthHistoryMetric = .steps

    var body: some View {
        HistoryChartView(
            navigationTitle: "Health History",
            filterStateToken: selectedMetric.rawValue.hashValue,
            filterControls: {
                metricPicker
            },
            pointsLoader: HealthHistoryChartSupport.pointsLoader(
                store: healthKitDailyStore,
                userIdProvider: { userService.currentUser?.id.uuidString },
                metricProvider: { selectedMetric }
            ),
            loadIntervalProvider: { interval, timeframe in
                HistoryChartLoadSupport.bufferedInterval(for: interval, timeframe: timeframe)
            },
            dataBoundsProvider: {
                guard let userId = userService.currentUser?.id.uuidString else { return (nil, nil) }
                if let bounds = try? healthKitDailyStore.cachedDataBounds(userId: userId), bounds.oldest != nil {
                    return bounds
                }
                let fallbackStart = Calendar.current.date(byAdding: .year, value: -5, to: Date())
                return (fallbackStart, Date())
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
}
