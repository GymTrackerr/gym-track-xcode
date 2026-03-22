import SwiftUI

struct HealthHistoryChartView: View {
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var healthKitDailyStore: HealthKitDailyStore

    @State private var selectedMetric: HealthHistoryMetric = .steps
    @State private var debugStatus: String = ""

    var body: some View {
        HistoryChartView(
            navigationTitle: "Health History",
            filterStateToken: loaderStateToken,
            filterControls: {
                metricPicker
            },
            pointsLoader: { interval, timeframe in
                let metric = selectedMetric
                let loader = HealthHistoryChartSupport.pointsLoader(
                    store: healthKitDailyStore,
                    userIdProvider: { userService.currentUser?.id.uuidString },
                    metricProvider: { metric }
                )
                let points = try await loader(interval, timeframe)
#if DEBUG
                let nonZeroCount = points.filter { $0.value > 0 }.count
                let status = "\(metric.title) | \(timeframe.rawValue) | points: \(points.count) | nonZero: \(nonZeroCount)"
                await MainActor.run {
                    debugStatus = status
                }
#endif
                return points
            },
            loadIntervalProvider: { interval, timeframe in
                HistoryChartLoadSupport.bufferedInterval(for: interval, timeframe: timeframe)
            },
            dataBoundsProvider: {
                guard let userId = userService.currentUser?.id.uuidString else { return (nil, nil) }
                if let bounds = try? healthKitDailyStore.cachedDataBounds(userId: userId), bounds.oldest != nil {
                    let now = Date()
                    let calendar = Calendar.current
                    let minAllowed = calendar.date(byAdding: .year, value: -6, to: now) ?? now
                    let maxAllowed = calendar.date(byAdding: .day, value: 1, to: now) ?? now
                    let clampedOldest = max(bounds.oldest ?? minAllowed, minAllowed)
                    let clampedNewest = min(bounds.newest ?? now, maxAllowed)
                    if clampedNewest > clampedOldest {
                        return (clampedOldest, clampedNewest)
                    }
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
#if DEBUG
        .safeAreaInset(edge: .bottom) {
            Text(debugStatus)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
#endif
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

    private var loaderStateToken: Int {
        var hasher = Hasher()
        hasher.combine(selectedMetric.rawValue)
        hasher.combine(userService.currentUser?.id.uuidString ?? "no-user")
        return hasher.finalize()
    }
}
