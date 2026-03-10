import SwiftUI

struct NutritionHistoryChartView: View {
    @EnvironmentObject var nutritionService: NutritionService

    @State private var selectedMetric: NutritionHistoryMetric = .calories

    var body: some View {
        HistoryChartView(
            navigationTitle: "Nutrition History",
            filterStateToken: selectedMetric.rawValue.hashValue,
            filterControls: {
                metricPicker
            },
            pointsProvider: { interval, timeframe in
                let logs = (try? nutritionService.logsInDateInterval(interval)) ?? []
                return NutritionChartCalculator.nutritionPoints(
                    logs: logs,
                    interval: interval,
                    timeframe: timeframe,
                    metric: selectedMetric
                )
            },
            dataBoundsProvider: {
                (try? nutritionService.nutritionBounds(for: selectedMetric.seriesMetric)) ?? (nil, nil)
            },
            summaryProvider: { selectedPoint, currentWindowAverage, _ in
                let value = selectedPoint?.value ?? currentWindowAverage
                return HistoryChartSummary(
                    title: selectedPoint == nil ? "AVG \(selectedMetric.title.uppercased())" : "SELECTED",
                    valueText: valueText(for: value),
                    unitText: selectedMetric.unitLabel
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
                ForEach(NutritionHistoryMetric.allCases) { metric in
                    HistoryChartChip(title: metric.title, isSelected: selectedMetric == metric) {
                        selectedMetric = metric
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .overlay(HistoryChartHorizontalScrollHints())
    }

    private func valueText(for value: Double) -> String {
        if selectedMetric == .calories {
            return String(Int(value.rounded()))
        }
        return SetDisplayFormatter.formatDecimal(value)
    }

}
