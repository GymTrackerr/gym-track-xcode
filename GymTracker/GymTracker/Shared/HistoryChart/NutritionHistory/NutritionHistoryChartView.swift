import SwiftUI

struct NutritionHistoryChartView: View {
    @EnvironmentObject var nutritionService: NutritionService
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var healthKitDailyStore: HealthKitDailyStore

    @State private var selectedMetric: NutritionHistoryMetric = .calories

    var body: some View {
        HistoryChartView(
            navigationTitle: "Nutrition History",
            filterStateToken: selectedMetric.rawValue.hashValue,
            filterControls: {
                metricPicker
            },
            pointsProvider: { interval, timeframe in
                switch selectedMetric {
                case .energyBalance:
                    guard let userId = userService.currentUser?.id.uuidString else {
                        return []
                    }
                    let logs = (try? nutritionService.logsInDateInterval(interval)) ?? []
                    let health = (try? healthKitDailyStore.cachedDailySummaries(in: interval, userId: userId)) ?? []
                    return NutritionChartCalculator.energyBalancePoints(
                        logs: logs,
                        healthSummaries: health,
                        interval: interval,
                        timeframe: timeframe
                    )
                default:
                    let logs = (try? nutritionService.logsInDateInterval(interval)) ?? []
                    return NutritionChartCalculator.nutritionPoints(
                        logs: logs,
                        interval: interval,
                        timeframe: timeframe,
                        metric: selectedMetric
                    )
                }
            },
            dataBoundsProvider: {
                if selectedMetric == .energyBalance {
                    return energyBalanceBounds()
                }
                return (try? nutritionService.nutritionBounds(for: selectedMetric.seriesMetric)) ?? (nil, nil)
            },
            summaryProvider: { selectedPoint, currentWindowAverage, _ in
                if selectedMetric == .energyBalance {
                    return energyBalanceSummary(selectedPoint: selectedPoint, currentWindowAverage: currentWindowAverage)
                }
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

    private func energyBalanceBounds() -> (oldest: Date?, newest: Date?) {
        let rawNutritionBounds = (try? nutritionService.nutritionBounds(for: .calories)) ?? (nil, nil)
        let nutritionBounds: (oldest: Date?, newest: Date?) = (rawNutritionBounds.0, rawNutritionBounds.1)
        guard let userId = userService.currentUser?.id.uuidString else {
            return nutritionBounds
        }

        let health = (try? healthKitDailyStore.cachedDailySummaries(userId: userId)) ?? []
        let energyHealth = health.filter { ($0.activeEnergyKcal + $0.restingEnergyKcal) > 0 }
        let healthOldest = energyHealth.min(by: { $0.dayStart < $1.dayStart })?.dayStart
        let healthNewest = energyHealth.max(by: { $0.dayStart < $1.dayStart })?.dayStart

        return (
            oldest: minDate(nutritionBounds.oldest, healthOldest),
            newest: maxDate(nutritionBounds.newest, healthNewest)
        )
    }

    private func energyBalanceSummary(
        selectedPoint: HistoryChartPoint?,
        currentWindowAverage: Double
    ) -> HistoryChartSummary {
        guard let selectedPoint else {
            return HistoryChartSummary(
                title: "AVG TOTAL ENERGY",
                valueText: String(Int(currentWindowAverage.rounded())),
                unitText: "kcal"
            )
        }

        let resting = selectedPoint.segmentValue(for: NutritionChartCalculator.restingSegmentKey) ?? 0
        let active = selectedPoint.segmentValue(for: NutritionChartCalculator.activeSegmentKey) ?? 0
        let eaten = selectedPoint.segmentValue(for: NutritionChartCalculator.eatenSegmentKey) ?? 0
        let balance = eaten - (resting + active)
        let title: String
        if balance > 0 {
            title = "SURPLUS"
        } else if balance < 0 {
            title = "DEFICIT"
        } else {
            title = "BALANCED"
        }

        return HistoryChartSummary(
            title: title,
            valueText: String(Int(abs(balance).rounded())),
            unitText: "kcal"
        )
    }

    private func minDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (l?, r?):
            return min(l, r)
        case let (l?, nil):
            return l
        case let (nil, r?):
            return r
        default:
            return nil
        }
    }

    private func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (l?, r?):
            return max(l, r)
        case let (l?, nil):
            return l
        case let (nil, r?):
            return r
        default:
            return nil
        }
    }

    private func valueText(for value: Double) -> String {
        if selectedMetric == .calories || selectedMetric == .energyBalance {
            return String(Int(value.rounded()))
        }
        return SetDisplayFormatter.formatDecimal(value)
    }

}
