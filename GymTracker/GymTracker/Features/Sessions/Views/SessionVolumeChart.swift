import SwiftUI
import SwiftData
import Charts

struct SessionVolumeChart: View {
    let points: [SessionVolumeModuleView.VolumePoint]
    var chartHeight: CGFloat = 120

    var body: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Bucket", point.label),
                y: .value("Volume", point.value)
            )
            .foregroundStyle(Color.blue)
            .cornerRadius(4)
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

    private func axisLabel(for value: Double) -> String {
        if value >= 1000 {
            return "\(Int(value / 1000))k"
        }
        return "\(Int(value.rounded()))"
    }
}

struct SessionVolumeModuleView: View {
    enum Range: String, CaseIterable, Identifiable {
        case week = "Week"
        case month = "Month"
        case year = "Year"

        var id: String { rawValue }

        var averageLabel: String {
            switch self {
            case .week: return "Daily average"
            case .month: return "Weekly average"
            case .year: return "Monthly average"
            }
        }

        var totalLabel: String {
            switch self {
            case .week: return "Weekly total"
            case .month: return "Monthly total"
            case .year: return "Yearly total"
            }
        }

        var currentBucketLabel: String {
            switch self {
            case .week: return "Today"
            case .month: return "This week"
            case .year: return "This month"
            }
        }
    }

    struct VolumePoint: Identifiable {
        let id = UUID()
        let startDate: Date
        let endDate: Date
        let label: String
        let value: Double
    }

    private struct Bucket {
        let startDate: Date
        let endDate: Date
        let label: String
    }

    let module: DashboardModule

    @EnvironmentObject private var exerciseService: ExerciseService
    @Query(sort: [SortDescriptor(\Session.timestampDone, order: .forward)]) private var sessions: [Session]

    @State private var selectedRange: Range = .week

    private var activeRange: Range {
        module.size == .large ? selectedRange : .week
    }

    private var userSessions: [Session] {
        guard let userId = exerciseService.currentUser?.id else { return [] }
        return sessions.filter { $0.user_id == userId }
    }

    private var points: [VolumePoint] {
        let calendar = Calendar.current
        let now = Date()
        let buckets = buildBuckets(for: activeRange, calendar: calendar, now: now)

        return buckets.map { bucket in
            let total = userSessions.reduce(0.0) { result, session in
                let date = session.timestampDone
                guard date >= bucket.startDate && date < bucket.endDate else { return result }
                return result + SessionService.sessionVolumeInPounds(session)
            }
            return VolumePoint(
                startDate: bucket.startDate,
                endDate: bucket.endDate,
                label: bucket.label,
                value: total
            )
        }
    }

    private var total: Double {
        points.reduce(0) { $0 + $1.value }
    }

    private var average: Double {
        guard !points.isEmpty else { return 0 }
        return total / Double(points.count)
    }

    private var currentBucketValue: Double {
        points.last?.value ?? 0
    }

    var body: some View {
        if module.size == .medium || module.size == .large {
            VStack(alignment: .leading, spacing: module.size == .large ? 8 : 6) {
                Text("Volume (\(activeRange.rawValue.lowercased()))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if module.size == .large {
                    Picker("Range", selection: $selectedRange) {
                        ForEach(Range.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                NavigationLink {
                    ExerciseHistoryChartView()
                        .appBackground()
                } label: {
                    SessionVolumeChart(
                        points: points,
                        chartHeight: module.size == .large ? 140 : 105
                    )
                }
                .buttonStyle(.plain)

                if module.size == .medium {
                    Text("Total: \(SessionService.formattedPounds(total))  •  Avg: \(SessionService.formattedPounds(average))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(activeRange.currentBucketLabel): \(SessionService.formattedPounds(currentBucketValue))")
                        Text("\(activeRange.totalLabel): \(SessionService.formattedPounds(total))")
                        Text("\(activeRange.averageLabel): \(SessionService.formattedPounds(average))")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        } else {
            MetricCard(
                value: SessionService.formattedPounds(totalVolumeForWeek)
            )
        }
    }

    private var totalVolumeForWeek: Double {
        let weekPoints = pointsForRange(.week)
        return weekPoints.reduce(0) { $0 + $1.value }
    }

    private func pointsForRange(_ range: Range) -> [VolumePoint] {
        let calendar = Calendar.current
        let now = Date()
        let buckets = buildBuckets(for: range, calendar: calendar, now: now)

        return buckets.map { bucket in
            let total = userSessions.reduce(0.0) { result, session in
                let date = session.timestampDone
                guard date >= bucket.startDate && date < bucket.endDate else { return result }
                return result + SessionService.sessionVolumeInPounds(session)
            }
            return VolumePoint(
                startDate: bucket.startDate,
                endDate: bucket.endDate,
                label: bucket.label,
                value: total
            )
        }
    }

    private func buildBuckets(for range: Range, calendar: Calendar, now: Date) -> [Bucket] {
        switch range {
        case .week:
            return buildDailyBuckets(days: 7, calendar: calendar, now: now)
        case .month:
            return buildWeeklyBuckets(weeks: 5, calendar: calendar, now: now)
        case .year:
            return buildMonthlyBuckets(months: 12, calendar: calendar, now: now)
        }
    }

    private func buildDailyBuckets(days: Int, calendar: Calendar, now: Date) -> [Bucket] {
        let endDay = calendar.startOfDay(for: now)
        let startDay = calendar.date(byAdding: .day, value: -(days - 1), to: endDay) ?? endDay

        return (0..<days).compactMap { offset in
            guard let start = calendar.date(byAdding: .day, value: offset, to: startDay),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else {
                return nil
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "E"
            return Bucket(
                startDate: start,
                endDate: end,
                label: formatter.string(from: start)
            )
        }
    }

    private func buildWeeklyBuckets(weeks: Int, calendar: Calendar, now: Date) -> [Bucket] {
        let today = calendar.startOfDay(for: now)
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let firstWeekStart = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: currentWeekStart) ?? currentWeekStart

        return (0..<weeks).compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: offset, to: firstWeekStart),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else {
                return nil
            }

            let weekNumber = calendar.component(.weekOfYear, from: start)
            return Bucket(
                startDate: start,
                endDate: end,
                label: "W\(weekNumber)"
            )
        }
    }

    private func buildMonthlyBuckets(months: Int, calendar: Calendar, now: Date) -> [Bucket] {
        let today = calendar.startOfDay(for: now)
        let currentMonthStart = calendar.dateInterval(of: .month, for: today)?.start ?? today
        let firstMonthStart = calendar.date(byAdding: .month, value: -(months - 1), to: currentMonthStart) ?? currentMonthStart

        return (0..<months).compactMap { offset in
            guard let start = calendar.date(byAdding: .month, value: offset, to: firstMonthStart),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else {
                return nil
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "MMM"
            return Bucket(
                startDate: start,
                endDate: end,
                label: formatter.string(from: start)
            )
        }
    }

}
