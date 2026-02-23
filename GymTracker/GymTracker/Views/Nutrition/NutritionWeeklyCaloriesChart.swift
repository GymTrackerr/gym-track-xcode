import SwiftUI
import SwiftData
import Charts

struct NutritionWeeklyCaloriesChart: View {
    let points: [NutritionService.DailyNutritionPoint]
    let metric: NutritionService.NutritionSeriesMetric
    var chartHeight: CGFloat = 120

    var body: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Day", point.date, unit: .day),
                y: .value(metric.displayName, point.value)
            )
            .foregroundStyle(metricColor)
            .cornerRadius(4)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(shortDay(from: date))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let raw = value.as(Double.self) {
                        Text(axisLabel(for: raw))
                            .font(.caption2)
                    }
                }
                .offset(x: -2)
            }
        }
        .frame(height: chartHeight)
    }

    private var metricColor: Color {
        switch metric {
        case .calories:
            return Color.blue
        case .protein:
            return Color.blue.opacity(0.9)
        case .carbs:
            return Color.blue.opacity(0.8)
        case .fat:
            return Color.blue.opacity(0.7)
        }
    }

    private func shortDay(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }

    private func axisLabel(for value: Double) -> String {
        if metric == .calories {
            if value >= 1000 {
                return "\(Int(value / 1000))k"
            }
            return "\(Int(value.rounded()))"
        }
        return "\(Int(value.rounded()))"
    }
}

struct NutritionWeeklyCaloriesModule: View {
    let module: DashboardModule

    @EnvironmentObject private var nutritionService: NutritionService
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: [SortDescriptor(\FoodLog.timestamp, order: .reverse)]) private var logs: [FoodLog]

    @State private var selectedMetric: NutritionService.NutritionSeriesMetric = .calories
    @State private var points: [NutritionService.DailyNutritionPoint] = []

    private var effectiveMetric: NutritionService.NutritionSeriesMetric {
        module.size == .large ? selectedMetric : .calories
    }

    private var total: Double {
        points.reduce(0) { $0 + $1.value }
    }

    private var average: Double {
        guard !points.isEmpty else { return 0 }
        return total / Double(points.count)
    }

    private var todayValue: Double {
        points.last?.value ?? 0
    }

    private var logsSignature: Int {
        logs.reduce(into: 0) { result, log in
            result ^= log.id.hashValue
            result ^= Int(log.timestamp.timeIntervalSince1970)
            result ^= Int((log.grams * 10).rounded())
            result ^= Int(((log.quickCaloriesKcal ?? -1) * 10).rounded())
        }
    }

    private var hasLogsInRange: Bool {
        guard let userId = nutritionService.currentUser?.id else { return false }
        let calendar = Calendar.current
        let endDayStart = calendar.startOfDay(for: Date())
        let startDay = calendar.date(byAdding: .day, value: -6, to: endDayStart) ?? endDayStart
        let rangeEnd = calendar.date(byAdding: .day, value: 1, to: endDayStart) ?? endDayStart

        return logs.contains {
            $0.userId == userId && $0.timestamp >= startDay && $0.timestamp < rangeEnd
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: module.size == .large ? 8 : 6) {
            Text(metricTitle)
                .font(.caption)
                .foregroundColor(.secondary)

            if module.size == .large {
                Picker("Metric", selection: $selectedMetric) {
                    ForEach(NutritionService.NutritionSeriesMetric.allCases) { metric in
                        Text(metric.displayName).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
            }

            NutritionWeeklyCaloriesChart(
                points: points,
                metric: effectiveMetric,
                chartHeight: module.size == .large ? 140 : 105
            )

            if !hasLogsInRange {
                Text("No logs yet")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if module.size == .medium {
                Text("Total: \(formatted(total, metric: .calories))  •  Avg: \(formatted(average, metric: .calories))")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            } else if module.size == .large {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today: \(formatted(todayValue, metric: effectiveMetric))")
                    Text("Weekly total: \(formatted(total, metric: effectiveMetric))")
                    Text("Weekly average: \(formatted(average, metric: effectiveMetric))")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
        .onAppear {
            refreshSeries()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                refreshSeries()
            }
        }
        .onChange(of: logsSignature) {
            refreshSeries()
        }
        .onChange(of: selectedMetric) {
            if module.size == .large {
                refreshSeries()
            }
        }
    }

    private var metricTitle: String {
        if module.size == .large {
            return "\(effectiveMetric.displayName) (7d)"
        }
        return "Calories (7d)"
    }

    private func refreshSeries() {
        do {
            points = try nutritionService.dailyNutritionSeries(
                endingOn: Date(),
                days: 7,
                metric: effectiveMetric
            )
        } catch {
            points = fallbackSeries()
        }
    }

    private func fallbackSeries() -> [NutritionService.DailyNutritionPoint] {
        let calendar = Calendar.current
        let endDayStart = calendar.startOfDay(for: Date())
        let startDay = calendar.date(byAdding: .day, value: -6, to: endDayStart) ?? endDayStart
        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: startDay) ?? startDay
            return NutritionService.DailyNutritionPoint(date: date, value: 0)
        }
    }

    private func formatted(_ value: Double, metric: NutritionService.NutritionSeriesMetric) -> String {
        switch metric {
        case .calories:
            return "\(Int(value.rounded())) kcal"
        case .protein, .carbs, .fat:
            return "\(Int(value.rounded())) g"
        }
    }
}
