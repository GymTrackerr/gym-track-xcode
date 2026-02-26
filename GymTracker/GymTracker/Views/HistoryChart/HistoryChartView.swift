import SwiftUI
import Charts

struct HistoryChartSummary {
    let title: String
    let valueText: String
    let unitText: String?
}

struct HistoryChartView<FilterControls: View>: View {
    let navigationTitle: String
    let filterStateToken: Int
    let filterControls: () -> FilterControls
    let pointsProvider: (DateInterval, HistoryChartTimeframe) -> [HistoryChartPoint]
    let dataBoundsProvider: () -> (oldest: Date?, newest: Date?)
    let summaryProvider: (HistoryChartPoint?, Double, HistoryChartTimeframe) -> HistoryChartSummary
    let emptyStateTextProvider: (Int) -> String

    @State private var timeframe: HistoryChartTimeframe = .month
    @State private var anchorDate: Date = Date()
    @State private var chartScrollPosition: Date = Date()
    @State private var selectedPointId: TimeInterval?
    @State private var selectedXDate: Date?
    @State private var isChangingTimeframe = false

    // Cached data to avoid redundant recomputation on every scroll frame
    @State private var cachedPoints: [HistoryChartPoint] = []
    @State private var cachedDataBounds: (oldest: Date?, newest: Date?) = (nil, nil)
    @State private var chartWidth: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                timeframeHeader
                filterControls()
                summaryHeader

                Chart(cachedPoints) { point in
                    BarMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value),
                        width: .fixed(barWidth)
                    )
                    .cornerRadius(1.5)
                    .foregroundStyle(selectedPointId == nil || selectedPointId == point.id ? Color.blue : Color.blue.opacity(0.45))
                }
                .chartYAxis {
                    AxisMarks(position: .trailing) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.9, dash: [2, 3]))
                            .foregroundStyle(.secondary.opacity(0.5))
                        AxisValueLabel()
                    }
                }
                .chartXAxis {
                    if let axisDates = HistoryChartCalculator.axisMarkDates(for: timeframe, interval: fullScrollableInterval) {
                        AxisMarks(values: axisDates) { value in
                            if let date = value.as(Date.self) {
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.8, dash: [2, 3]))
                                    .foregroundStyle(.secondary.opacity(0.4))
                                AxisValueLabel {
                                    Text(HistoryChartCalculator.xAxisLabel(for: date, timeframe: timeframe))
                                }
                            }
                        }
                    } else {
                        AxisMarks(values: .automatic(desiredCount: 7)) { value in
                            if let date = value.as(Date.self) {
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.8, dash: [2, 3]))
                                    .foregroundStyle(.secondary.opacity(0.35))
                                AxisValueLabel {
                                    Text(HistoryChartCalculator.xAxisLabel(for: date, timeframe: timeframe))
                                }
                            }
                        }
                    }
                }
                .chartYScale(domain: 0...chartYMax)
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: visibleDomainLength)
                .chartXScale(domain: chartXDomain)
                .chartScrollPosition(x: $chartScrollPosition)
                .chartXSelection(value: $selectedXDate)
                .chartBackground { chartProxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onAppear {
                                if let plotFrame = chartProxy.plotFrame {
                                    chartWidth = geometry[plotFrame].width
                                }
                            }
                            .onChange(of: geometry.size) {
                                if let plotFrame = chartProxy.plotFrame {
                                    chartWidth = geometry[plotFrame].width
                                }
                            }
                            .onTapGesture { location in
                                guard let plotFrame = chartProxy.plotFrame else { return }
                                let frame = geometry[plotFrame]
                                let x = location.x - frame.origin.x

                                if x < 0 || x > frame.size.width {
                                    selectedPointId = nil
                                    selectedXDate = nil
                                } else if let date: Date = chartProxy.value(atX: x) {
                                    if !cachedPoints.contains(where: {
                                        date >= $0.startDate && date < $0.endDate && $0.value > 0
                                    }) {
                                        selectedPointId = nil
                                        selectedXDate = nil
                                    }
                                }
                            }
                    }
                }
                .onChange(of: chartScrollPosition) { _, newValue in
                    guard !isChangingTimeframe else { return }

                    let maxScroll = latestAllowedDate
                    let clamped = max(earliestAllowedWindowStart, min(newValue, maxScroll))
                    if clamped != newValue {
                        chartScrollPosition = clamped
                        return
                    }

                    selectedPointId = nil
                    selectedXDate = nil
                }
                .onChange(of: selectedXDate) { _, newValue in
                    guard let newValue else {
                        selectedPointId = nil
                        return
                    }
                    updateSelectedPoint(for: newValue)
                }
                .frame(height: 280)
                .padding(12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                if cachedPoints.allSatisfy({ $0.value == 0 }) {
                    Text(emptyStateTextProvider(cachedPoints.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding()
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            cachedDataBounds = dataBoundsProvider()
            anchorDate = cachedDataBounds.newest ?? Date()
            resetToCurrentWindow()
        }
        .onChange(of: timeframe) { _, _ in
            isChangingTimeframe = true
            cachedDataBounds = dataBoundsProvider()
            resetToCurrentWindow()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isChangingTimeframe = false
            }
        }
        .onChange(of: filterStateToken) { _, _ in
            isChangingTimeframe = true
            cachedDataBounds = dataBoundsProvider()
            resetToCurrentWindow()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isChangingTimeframe = false
            }
        }
    }

    private var timeframeHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    shiftWindow(direction: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .padding(8)
                }
                .buttonStyle(.bordered)
                .disabled(isPreviousDisabled)

                Spacer()

                Text(intervalTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Spacer()

                Button {
                    shiftWindow(direction: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .padding(8)
                }
                .buttonStyle(.bordered)
                .disabled(isNextDisabled)
            }

            Picker("Timeframe", selection: $timeframe) {
                ForEach(HistoryChartTimeframe.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var summaryHeader: some View {
        let summary = summaryProvider(selectedPoint, currentWindowAverageValue, timeframe)

        return VStack(alignment: .leading, spacing: 2) {
            Text(summary.title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(summary.valueText)
                    .font(.title)
                    .fontWeight(.bold)
                if let unitText = summary.unitText {
                    Text(unitText)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
            Text(summaryDateText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var currentWindowInterval: DateInterval {
        HistoryChartCalculator.currentWindow(for: timeframe, now: anchorDate)
    }

    private var selectedPoint: HistoryChartPoint? {
        guard let selectedPointId else { return nil }
        return cachedPoints.first { $0.id == selectedPointId }
    }

    private var visibleWindowInterval: DateInterval {
        let midpoint = chartScrollPosition.addingTimeInterval(visibleDomainLength / 2)
        let scrolledAnchor = snappedRangeStart(for: midpoint)
        return HistoryChartCalculator.currentWindow(for: timeframe, now: scrolledAnchor)
    }

    private var fullScrollableInterval: DateInterval {
        let start = earliestAllowedWindowStart
        let end = max(latestAllowedDate, start.addingTimeInterval(1))
        return DateInterval(start: start, end: end)
    }

    private var latestAllowedDate: Date {
        HistoryChartCalculator.currentWindow(for: timeframe, now: Date()).end
    }

    private var visibleDomainLength: TimeInterval {
        HistoryChartCalculator.visibleDomainLength(for: timeframe)
    }

    private var visibleInterval: DateInterval {
        let start = chartScrollPosition
        let end = start.addingTimeInterval(visibleDomainLength)
        return DateInterval(start: start, end: end)
    }

    private var chartYMax: Double {
        let visiblePoints = cachedPoints.filter { point in
            point.startDate < visibleInterval.end && point.endDate > visibleInterval.start
        }
        let maxValue = visiblePoints.map(\.value).max() ?? cachedPoints.map(\.value).max() ?? 0
        return max(maxValue * 1.15, 1)
    }

    private var chartXDomain: ClosedRange<Date> {
        earliestAllowedWindowStart...latestAllowedDate
    }

    private var barWidth: CGFloat {
        guard chartWidth > 0 else { return 10 }
        let slotWidth = chartWidth / CGFloat(timeframe.barsPerWindow)
        return max(slotWidth * timeframe.barFillRatio, 4)
    }

    private var summaryDateText: String {
        if let selectedPoint {
            return HistoryChartCalculator.selectionLabel(for: selectedPoint, timeframe: timeframe)
        }
        let start = visibleInterval.start.formatted(date: .abbreviated, time: .omitted)
        let end = visibleInterval.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted)
        return "\(start) - \(end)"
    }

    private var currentWindowAverageValue: Double {
        let points = cachedPoints.filter { point in
            point.startDate >= currentWindowInterval.start && point.startDate < currentWindowInterval.end && point.value > 0
        }
        guard !points.isEmpty else { return 0 }
        return points.reduce(0.0) { $0 + $1.value } / Double(points.count)
    }

    private var intervalTitle: String {
        let calendar = Calendar.current
        let snappedInterval = visibleWindowInterval
        let start = snappedInterval.start
        let end = snappedInterval.end.addingTimeInterval(-1)
        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale.current
        monthFormatter.setLocalizedDateFormatFromTemplate("MMM")
        let yearFormatter = DateFormatter()
        yearFormatter.locale = Locale.current
        yearFormatter.setLocalizedDateFormatFromTemplate("yyyy")

        switch timeframe {
        case .week:
            let startMonth = monthFormatter.string(from: start)
            let endMonth = monthFormatter.string(from: end)
            let startDay = calendar.component(.day, from: start)
            let endDay = calendar.component(.day, from: end)
            let endYear = yearFormatter.string(from: end)
            if calendar.component(.month, from: start) == calendar.component(.month, from: end) {
                return "\(startMonth) \(startDay)-\(endDay), \(endYear)"
            }
            return "\(startMonth) \(startDay) - \(endMonth) \(endDay), \(endYear)"
        case .month:
            let monthYearFormatter = DateFormatter()
            monthYearFormatter.locale = Locale.current
            monthYearFormatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
            return monthYearFormatter.string(from: start)
        case .sixMonths:
            let startMonth = monthFormatter.string(from: start)
            let endMonth = monthFormatter.string(from: end)
            let endYear = yearFormatter.string(from: end)
            return "\(startMonth) - \(endMonth) \(endYear)"
        case .year:
            return yearFormatter.string(from: start)
        case .fiveYears:
            let startYear = yearFormatter.string(from: start)
            let endYear = yearFormatter.string(from: end)
            return "\(startYear) - \(endYear)"
        }
    }

    private var isNextDisabled: Bool {
        let currentVisible = snappedRangeStart(for: chartScrollPosition)
        let shifted = HistoryChartCalculator.shift(anchorDate: currentVisible, timeframe: timeframe, direction: 1)
        return HistoryChartCalculator.currentWindow(for: timeframe, now: shifted).start > Date()
    }

    private var isPreviousDisabled: Bool {
        let currentVisible = snappedRangeStart(for: chartScrollPosition)
        let shifted = HistoryChartCalculator.shift(anchorDate: currentVisible, timeframe: timeframe, direction: -1)
        return HistoryChartCalculator.currentWindow(for: timeframe, now: shifted).start < earliestAllowedWindowStart
    }

    private var earliestAllowedWindowStart: Date {
        guard let oldestDataDate = cachedDataBounds.oldest else { return currentWindowInterval.start }
        return HistoryChartCalculator.currentWindow(for: timeframe, now: oldestDataDate).start
    }

    private func shiftWindow(direction: Int) {
        let currentVisible = snappedRangeStart(for: chartScrollPosition)
        let shifted = HistoryChartCalculator.shift(anchorDate: currentVisible, timeframe: timeframe, direction: direction)
        if direction > 0 {
            let shiftedInterval = HistoryChartCalculator.currentWindow(for: timeframe, now: shifted)
            guard shiftedInterval.start <= Date() else { return }
        } else {
            let shiftedInterval = HistoryChartCalculator.currentWindow(for: timeframe, now: shifted)
            guard shiftedInterval.start >= earliestAllowedWindowStart else { return }
        }

        anchorDate = shifted
        let newWindow = HistoryChartCalculator.currentWindow(for: timeframe, now: shifted)

        let loadRange = DateInterval(start: earliestAllowedWindowStart, end: latestAllowedDate)
        cachedPoints = pointsProvider(loadRange, timeframe)
        chartScrollPosition = newWindow.start
        selectedPointId = nil
        selectedXDate = nil
    }

    private func resetToCurrentWindow() {
        let window = currentWindowInterval

        let loadRange = DateInterval(start: earliestAllowedWindowStart, end: latestAllowedDate)
        cachedPoints = pointsProvider(loadRange, timeframe)
        chartScrollPosition = window.start
        selectedPointId = nil
        selectedXDate = nil
    }

    private func updateSelectedPoint(for date: Date) {
        guard !cachedPoints.isEmpty else {
            selectedPointId = nil
            return
        }
        // Exact bucket match
        if let exact = cachedPoints.first(where: { date >= $0.startDate && date < $0.endDate && $0.value > 0 }) {
            selectedPointId = exact.id
            return
        }
        // Closest non-zero point by midpoint distance
        let nonZero = cachedPoints.filter { $0.value > 0 }
        if let closest = nonZero.min(by: {
            let mid0 = $0.startDate.addingTimeInterval($0.endDate.timeIntervalSince($0.startDate) / 2)
            let mid1 = $1.startDate.addingTimeInterval($1.endDate.timeIntervalSince($1.startDate) / 2)
            return abs(date.timeIntervalSince(mid0)) < abs(date.timeIntervalSince(mid1))
        }) {
            let closestMid = closest.startDate.addingTimeInterval(closest.endDate.timeIntervalSince(closest.startDate) / 2)
            let maxSnapDistance = (closest.endDate.timeIntervalSince(closest.startDate)) * 1.5
            if abs(date.timeIntervalSince(closestMid)) <= maxSnapDistance {
                selectedPointId = closest.id
                return
            }
        }
        selectedPointId = nil
    }

    private func snappedRangeStart(for date: Date) -> Date {
        Calendar.current.dateInterval(of: timeframe.windowCalendarComponent, for: date)?.start ?? date
    }
}

// MARK: - Shared UI Components

struct HistoryChartChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(isSelected ? Color.blue : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct HistoryChartHorizontalScrollHints: View {
    var body: some View {
        HStack {
            Image(systemName: "chevron.left")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 4)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.trailing, 4)
        }
        .allowsHitTesting(false)
        .opacity(0.45)
    }
}
