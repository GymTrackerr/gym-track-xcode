import SwiftUI
import Charts
#if canImport(UIKit)
import UIKit
#endif

struct HistoryChartSummary {
    let title: String
    let valueText: String
    let unitText: String?
}

struct HistoryChartSummaryDetail: Identifiable {
    let title: String
    let valueText: String
    let unitText: String?

    var id: String {
        [title, valueText, unitText ?? ""].joined(separator: "|")
    }
}

struct HistoryChartView<FilterControls: View>: View {
    let navigationTitle: String
    let filterStateToken: Int
    let filterControls: () -> FilterControls
    let pointsProvider: (DateInterval, HistoryChartTimeframe) -> [HistoryChartPoint]
    let loadIntervalProvider: HistoryChartLoadIntervalProvider
    let dataBoundsProvider: () -> (oldest: Date?, newest: Date?)
    let summaryProvider: (HistoryChartPoint?, Double, HistoryChartTimeframe) -> HistoryChartSummary
    let summaryDetailsProvider: (HistoryChartPoint?, Double, HistoryChartTimeframe) -> [HistoryChartSummaryDetail]
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
    @State private var isLoadingPoints = false
    @State private var didAttemptLoad = false
    @State private var loadErrorText: String?
    @State private var isViewActive = false
    @State private var yAxisStickyMax: Double = 1
    @State private var yAxisStickyMin: Double = 0
    @State private var lastRequestedLoadSignature: String?
    @State private var loadedCoverageInterval: DateInterval?

    init(
        navigationTitle: String,
        filterStateToken: Int,
        filterControls: @escaping () -> FilterControls,
        pointsProvider: @escaping (DateInterval, HistoryChartTimeframe) -> [HistoryChartPoint],
        loadIntervalProvider: @escaping HistoryChartLoadIntervalProvider = { interval, timeframe in
            HistoryChartLoadSupport.bufferedInterval(for: interval, timeframe: timeframe)
        },
        dataBoundsProvider: @escaping () -> (oldest: Date?, newest: Date?),
        summaryProvider: @escaping (HistoryChartPoint?, Double, HistoryChartTimeframe) -> HistoryChartSummary,
        summaryDetailsProvider: @escaping (HistoryChartPoint?, Double, HistoryChartTimeframe) -> [HistoryChartSummaryDetail] = { _, _, _ in [] },
        emptyStateTextProvider: @escaping (Int) -> String
    ) {
        self.navigationTitle = navigationTitle
        self.filterStateToken = filterStateToken
        self.filterControls = filterControls
        self.pointsProvider = pointsProvider
        self.loadIntervalProvider = loadIntervalProvider
        self.dataBoundsProvider = dataBoundsProvider
        self.summaryProvider = summaryProvider
        self.summaryDetailsProvider = summaryDetailsProvider
        self.emptyStateTextProvider = emptyStateTextProvider
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                timeframeHeader
                filterControls()
                summaryHeader

                Chart(cachedPoints) { point in
                    if point.segments.isEmpty {
                        BarMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value),
                            width: .fixed(barWidth)
                        )
                        .cornerRadius(1.5)
                        .foregroundStyle(selectedPointId == nil || selectedPointId == point.id ? Color.blue : Color.blue.opacity(0.45))
                    } else {
                        ForEach(point.segments.filter { $0.value != 0 }) { segment in
                            BarMark(
                                x: .value("Date", point.date),
                                y: .value("Value", segment.value),
                                width: .fixed(barWidth)
                            )
                            .cornerRadius(1.5)
                            .foregroundStyle(segmentColor(for: segment.style).opacity(selectedPointId == nil || selectedPointId == point.id ? 1 : 0.45))
                        }
                    }
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
                .chartYScale(domain: chartYMin...chartYMax)
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
                                        date >= $0.startDate && date < $0.endDate && $0.plottedValue != 0
                                    }) {
                                        selectedPointId = nil
                                        selectedXDate = nil
                                    }
                                }
                            }
                    }
                }
                .onChange(of: chartScrollPosition) { _, newValue in
                    guard isViewActive, !isChangingTimeframe, didAttemptLoad else { return }
                    
                    // Clamp to valid bounds immediately (handles framework mutations to 2001-01-01)
                    let maxScroll = latestAllowedDate
                    let clamped = max(earliestAllowedWindowStart, min(newValue, maxScroll))
                    if clamped != newValue {
                        chartScrollPosition = clamped
                        return
                    }
                    
                    selectedPointId = nil
                    selectedXDate = nil
                    let activeTimeframe = timeframe
                    // Snap load requests to window boundaries so drag updates don't trigger redundant loads.
                    let snappedStart = snappedRangeStart(for: clamped)
                    let requestedInterval = visibleInterval(start: snappedStart, timeframe: activeTimeframe)
                    guard needsLoad(for: requestedInterval) else { return }
                    startLoad(for: requestedInterval, timeframe: activeTimeframe)
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

                if isLoadingPoints {
                    Text("Loading...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                } else if let loadErrorText {
                    Text(loadErrorText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                } else if didAttemptLoad && (cachedPoints.isEmpty || cachedPoints.allSatisfy({ $0.plottedValue == 0 })) {
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
            isViewActive = true
            chartWidth = 0
            refreshCachedBounds()
            anchorDate = cachedDataBounds.newest ?? Date()
            let initialWindow = currentWindowInterval(for: timeframe)
            resetToWindow(initialWindow)
            startLoad(for: initialWindow, timeframe: timeframe)
        }
        .onDisappear {
            isViewActive = false
            isLoadingPoints = false
            isChangingTimeframe = false
            lastRequestedLoadSignature = nil
            loadedCoverageInterval = nil
        }
        .onChange(of: timeframe) { _, newTimeframe in
            guard isViewActive else { return }
            isChangingTimeframe = true
            refreshCachedBounds()
            let timeframeWindow = currentWindowInterval(for: newTimeframe)
            resetToWindow(timeframeWindow)
            startLoad(for: timeframeWindow, timeframe: newTimeframe)
        }
        .onChange(of: filterStateToken) { _, _ in
            guard isViewActive else { return }
            isChangingTimeframe = true
            refreshCachedBounds()
            let filterWindow = currentWindowInterval(for: timeframe)
            resetToWindow(filterWindow)
            startLoad(for: filterWindow, timeframe: timeframe)
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
        let details = summaryDetailsProvider(selectedPoint, currentWindowAverageValue, timeframe)

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

            if !details.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(details) { detail in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(detail.title)
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                HStack(alignment: .firstTextBaseline, spacing: 3) {
                                    Text(detail.valueText)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                    if let unitText = detail.unitText {
                                        Text(unitText)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var currentWindowInterval: DateInterval {
        HistoryChartCalculator.currentWindow(for: timeframe, now: anchorDate)
    }

    private func currentWindowInterval(for timeframe: HistoryChartTimeframe) -> DateInterval {
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
        latestAllowedDate(for: timeframe)
    }

    private func latestAllowedDate(for timeframe: HistoryChartTimeframe) -> Date {
        HistoryChartCalculator.currentWindow(for: timeframe, now: Date()).end
    }

    private var visibleDomainLength: TimeInterval {
        HistoryChartCalculator.visibleDomainLength(for: timeframe)
    }

    private var visibleInterval: DateInterval {
        visibleInterval(start: chartScrollPosition, timeframe: timeframe)
    }

    private func visibleInterval(start: Date, timeframe: HistoryChartTimeframe) -> DateInterval {
        let length = HistoryChartCalculator.visibleDomainLength(for: timeframe)
        return DateInterval(start: start, end: start.addingTimeInterval(length))
    }

    private var chartYMax: Double {
        let visiblePoints = cachedPoints.filter { point in
            point.startDate < visibleInterval.end && point.endDate > visibleInterval.start
        }
        let maxValue = visiblePoints.map(\.plottedValue).max() ?? cachedPoints.map(\.plottedValue).max() ?? 0
        let roundedTarget = max(maxValue * 1.15, 1)
        return max(yAxisStickyMax, roundedTarget)
    }

    private var chartYMin: Double {
        let visiblePoints = cachedPoints.filter { point in
            point.startDate < visibleInterval.end && point.endDate > visibleInterval.start
        }
        let minValue = visiblePoints.map(\.plottedValue).min() ?? cachedPoints.map(\.plottedValue).min() ?? 0
        guard minValue < 0 else { return 0 }
        let roundedTarget = min(minValue * 1.15, -1)
        return min(yAxisStickyMin, roundedTarget)
    }

    private var chartXDomain: ClosedRange<Date> {
        earliestAllowedWindowStart...latestAllowedDate
    }

    private var barWidth: CGFloat {
        let effectiveWidth: CGFloat
        if chartWidth > 0 {
            effectiveWidth = chartWidth
        } else {
#if os(iOS)
            effectiveWidth = max(UIScreen.main.bounds.width - 56, 120)
#else
            effectiveWidth = 280
#endif
        }
        let slotWidth = effectiveWidth / CGFloat(timeframe.barsPerWindow)
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
            point.startDate >= visibleInterval.start && point.startDate < visibleInterval.end && point.plottedValue != 0
        }
        guard !points.isEmpty else { return 0 }
        let numerator = points.reduce(0.0) { $0 + $1.effectiveSummaryAverageNumerator }
        let denominator = points.reduce(0.0) { $0 + max($1.effectiveSummaryAverageDenominator, 0) }
        guard denominator > 0 else { return 0 }
        return numerator / denominator
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
        earliestAllowedWindowStart(for: timeframe)
    }

    private func refreshCachedBounds() {
        let rawBounds = dataBoundsProvider()
        cachedDataBounds = HistoryChartCalculator.sanitizeBounds(oldest: rawBounds.oldest, newest: rawBounds.newest)
    }

    private func earliestAllowedWindowStart(for timeframe: HistoryChartTimeframe) -> Date {
        guard let oldestDataDate = cachedDataBounds.oldest else {
            return HistoryChartCalculator.currentWindow(for: timeframe, now: Date()).start
        }
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
        chartScrollPosition = newWindow.start
        selectedPointId = nil
        selectedXDate = nil
        startLoad(for: DateInterval(start: newWindow.start, end: newWindow.end), timeframe: timeframe)
    }

    private func startLoad(
        for interval: DateInterval,
        timeframe: HistoryChartTimeframe
    ) {
        // Clamp interval to valid bounds immediately
        let earliest = earliestAllowedWindowStart(for: timeframe)
        let latest = latestAllowedDate(for: timeframe)
        let clamped = DateInterval(start: max(interval.start, earliest), end: min(interval.end, latest))
        
        // Guard against invalid intervals
        guard clamped.end > clamped.start else {
            isLoadingPoints = false
            return
        }

        let signature = loadSignature(for: clamped, timeframe: timeframe)
        if signature == lastRequestedLoadSignature {
            return
        }
        lastRequestedLoadSignature = signature

        loadPoints(for: clamped, timeframe: timeframe)
        guard isViewActive else { return }
        isChangingTimeframe = false
    }

    private func resetToWindow(_ window: DateInterval) {
        chartScrollPosition = window.start
        selectedPointId = nil
        selectedXDate = nil
        cachedPoints = []
        yAxisStickyMax = 1
        yAxisStickyMin = 0
        lastRequestedLoadSignature = nil
        loadedCoverageInterval = nil
        didAttemptLoad = false
        loadErrorText = nil
    }

    private func needsLoad(for requestedInterval: DateInterval) -> Bool {
        guard let loadedCoverageInterval else { return true }
        return !(loadedCoverageInterval.start <= requestedInterval.start && loadedCoverageInterval.end >= requestedInterval.end)
    }

    private func loadSignature(for interval: DateInterval, timeframe: HistoryChartTimeframe) -> String {
        let start = Int(interval.start.timeIntervalSince1970)
        let end = Int(interval.end.timeIntervalSince1970)
        return "\(timeframe.rawValue):\(start):\(end)"
    }

    private func updateYAxisStickyMax(with points: [HistoryChartPoint]) {
        let maxValue = points.map(\.plottedValue).max() ?? 0
        let roundedTarget = max(maxValue * 1.15, 1)
        if roundedTarget > yAxisStickyMax {
            yAxisStickyMax = roundedTarget
        }

        let minValue = points.map(\.plottedValue).min() ?? 0
        if minValue < 0 {
            let minTarget = min(minValue * 1.15, -1)
            if minTarget < yAxisStickyMin {
                yAxisStickyMin = minTarget
            }
        }
    }

    private func updateSelectedPoint(for date: Date) {
        guard !cachedPoints.isEmpty else {
            selectedPointId = nil
            return
        }
        // Exact bucket match
        if let exact = cachedPoints.first(where: { date >= $0.startDate && date < $0.endDate && $0.plottedValue != 0 }) {
            selectedPointId = exact.id
            return
        }
        // Closest non-zero point by midpoint distance
        let nonZero = cachedPoints.filter { $0.plottedValue != 0 }
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

    private func loadPoints(for requestedVisibleInterval: DateInterval, timeframe requestedTimeframe: HistoryChartTimeframe) {
        guard isViewActive else { return }
        guard requestedVisibleInterval.end > requestedVisibleInterval.start else {
            isLoadingPoints = false
            didAttemptLoad = true
            return
        }
        
        let bounds = loadBounds(for: requestedTimeframe)
        let boundedStart = max(requestedVisibleInterval.start, bounds.earliest)
        let boundedEnd = min(requestedVisibleInterval.end, bounds.latest)
        guard boundedEnd > boundedStart else {
            isLoadingPoints = false
            didAttemptLoad = true
            return
        }

        let boundedInterval = DateInterval(start: boundedStart, end: boundedEnd)
        let candidateInterval = loadIntervalProvider(boundedInterval, requestedTimeframe)
        let loadInterval = candidateInterval.end > candidateInterval.start ? candidateInterval : boundedInterval
        
        // Guard one final time before calling loader
        guard loadInterval.end > loadInterval.start else {
            isLoadingPoints = false
            didAttemptLoad = true
            return
        }

        let points = pointsProvider(loadInterval, requestedTimeframe)
        cachedPoints = points
        updateYAxisStickyMax(with: points)
        loadedCoverageInterval = loadInterval
        isLoadingPoints = false
        didAttemptLoad = true
        loadErrorText = nil
        applySelectionAfterLoad()
    }

    private func loadBounds(for timeframe: HistoryChartTimeframe) -> (earliest: Date, latest: Date) {
        (
            earliest: earliestAllowedWindowStart(for: timeframe),
            latest: latestAllowedDate(for: timeframe)
        )
    }

    private func applySelectionAfterLoad() {
        guard let selectedXDate else {
            selectedPointId = nil
            return
        }
        updateSelectedPoint(for: selectedXDate)
    }

    private func segmentColor(for style: HistoryChartSegmentStyle) -> Color {
        switch style {
        case .primary:
            return .blue
        case .secondary:
            return .cyan
        case .tertiary:
            return .indigo
        case .positive:
            return .green
        case .warning:
            return .orange
        case .negative:
            return .red
        case .neutral:
            return .gray
        }
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
