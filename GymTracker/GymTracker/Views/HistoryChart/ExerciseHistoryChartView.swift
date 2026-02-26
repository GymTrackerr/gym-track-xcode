//
//  ExerciseHistoryChartView.swift
//  GymTracker
//
//  Created by Codex on 2026-02-26.
//

import SwiftUI
import Charts

struct ExerciseHistoryChartView: View {
    @EnvironmentObject var sessionService: SessionService

    enum DataScope {
        case allSessions
        case exercise(Exercise)
        case exerciseId(UUID)

        var exerciseId: UUID? {
            switch self {
            case .allSessions:
                return nil
            case .exercise(let exercise):
                return exercise.id
            case .exerciseId(let id):
                return id
            }
        }

        var title: String {
            switch self {
            case .allSessions:
                return "History"
            case .exercise(let exercise):
                return exercise.name
            case .exerciseId:
                return "History"
            }
        }

        var preferredMetricMode: ExerciseHistoryMetricMode? {
            switch self {
            case .exercise(let exercise):
                return exercise.cardio ? .cardio : .strength
            default:
                return nil
            }
        }
    }

    let scope: DataScope

    @State private var metricMode: ExerciseHistoryMetricMode = .strength
    @State private var timeframe: ExerciseHistoryTimeframe = .month
    @State private var anchorDate: Date = Date()
    @State private var selectedStrengthMetric: ProgressMetric = .totalVolume
    @State private var selectedCardioMetric: CardioProgressMetric = .totalDistance
    @State private var selectedWeightUnit: WeightUnit = .lb
    @State private var selectedDistanceUnit: DistanceUnit = .km

    @State private var chartScrollPosition: Date = Date()
    @State private var loadedWindows: [DateInterval] = []
    @State private var loadedSessions: [Session] = []
    @State private var actualLoadedInterval: DateInterval? = nil
    @State private var selectedPointId: TimeInterval? = nil
    @State private var selectedXDate: Date? = nil
    @State private var isChangingTimeframe = false

    init(exercise: Exercise? = nil, exerciseId: UUID? = nil) {
        if let exercise {
            self.scope = .exercise(exercise)
        } else if let exerciseId {
            self.scope = .exerciseId(exerciseId)
        } else {
            self.scope = .allSessions
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                timeframeHeader
                modePicker
                metricPicker
                unitPicker
                summaryHeader

                Chart(chartPoints) { point in
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
                    if let axisDates = ExerciseHistoryChartCalculator.axisMarkDates(for: timeframe, interval: fullScrollableInterval) {
                        AxisMarks(values: axisDates) { value in
                            if let date = value.as(Date.self) {
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.8, dash: [2, 3]))
                                    .foregroundStyle(.secondary.opacity(0.4))
                                AxisValueLabel {
                                    Text(ExerciseHistoryChartCalculator.xAxisLabel(for: date, timeframe: timeframe))
                                }
                            }
                        }
                    } else {
                        AxisMarks(values: .automatic(desiredCount: 7)) { value in
                            if let date = value.as(Date.self) {
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.8, dash: [2, 3]))
                                    .foregroundStyle(.secondary.opacity(0.35))
                                AxisValueLabel {
                                    Text(ExerciseHistoryChartCalculator.xAxisLabel(for: date, timeframe: timeframe))
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
                    // Handle clicks on empty areas to deselect
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                guard let plotFrame = chartProxy.plotFrame else { return }
                                let frame = geometry[plotFrame]
                                let x = location.x - frame.origin.x
                                
                                // Only deselect if clicking outside chart bounds or on empty space
                                if x < 0 || x > frame.size.width {
                                    selectedPointId = nil
                                    selectedXDate = nil
                                } else if let date: Date = chartProxy.value(atX: x) {
                                    // Check if this date has data
                                    if !chartPoints.contains(where: { 
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
                    // Don't update anchorDate during timeframe changes (risk of circular logic)
                    guard !isChangingTimeframe else { return }
                    
                    // Clamp scroll position to valid data range (allow scrolling through entire current window)
                    let maxScroll = latestAllowedDate
                    let clamped = max(earliestAllowedWindowStart, min(newValue, maxScroll))
                    if clamped != newValue {
                        chartScrollPosition = clamped
                        return
                    }
                    
                    // Clear selection when scrolling
                    selectedPointId = nil
                    selectedXDate = nil
                    
                    // Don't update anchorDate during free scrolling - let user navigate the loaded data
                    // Only update anchorDate when explicitly shifting windows with arrow buttons
                }
                .onChange(of: selectedXDate) { _, newValue in
                    guard let newValue else {
                        selectedPointId = nil
                        return
                    }
                    updateSelectedPoint(for: newValue)
                    extendLoadedIntervalIfNeeded(for: newValue)
                }
                .frame(height: 280)
                .padding(12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                if chartPoints.allSatisfy({ $0.value == 0 }) {
                    Text(emptyStateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding()
        }
        .navigationTitle(scope.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let preferredMode = scope.preferredMetricMode {
                metricMode = preferredMode
            }
            anchorDate = newestDataDate ?? Date()
            resetToCurrentWindow()
        }
        .onChange(of: timeframe) { _, _ in
            isChangingTimeframe = true
            resetToCurrentWindow()
            // Re-enable scroll change handling after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isChangingTimeframe = false
            }
        }
        .onChange(of: metricMode) { _, _ in
            isChangingTimeframe = true
            resetToCurrentWindow()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isChangingTimeframe = false
            }
        }
        .onChange(of: selectedStrengthMetric) { _, _ in
            if metricMode == .strength {
                selectedPointId = nil
                selectedXDate = nil
                resetToCurrentWindow()
            }
        }
        .onChange(of: selectedCardioMetric) { _, _ in
            if metricMode == .cardio {
                selectedPointId = nil
                selectedXDate = nil
                resetToCurrentWindow()
            }
        }
        .onChange(of: selectedWeightUnit) { _, _ in
            selectedPointId = nil
            selectedXDate = nil
        }
        .onChange(of: selectedDistanceUnit) { _, _ in
            selectedPointId = nil
            selectedXDate = nil
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
                ForEach(ExerciseHistoryTimeframe.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var modePicker: some View {
        Group {
            if scope.preferredMetricMode == nil {
                Picker("Mode", selection: $metricMode) {
                    ForEach(ExerciseHistoryMetricMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var metricPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if metricMode == .cardio {
                    ForEach(CardioProgressMetric.allCases) { metric in
                        metricChip(title: metric.title, isSelected: selectedCardioMetric == metric) {
                            selectedCardioMetric = metric
                        }
                    }
                } else {
                    ForEach(ProgressMetric.allCases) { metric in
                        metricChip(title: metric.title, isSelected: selectedStrengthMetric == metric) {
                            selectedStrengthMetric = metric
                        }
                    }
                }
            }
        }
        .overlay(horizontalScrollHints)
    }

    private var unitPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if metricMode == .cardio {
                    ForEach([DistanceUnit.km, DistanceUnit.mi], id: \.rawValue) { unit in
                        metricChip(title: unit.rawValue.uppercased(), isSelected: selectedDistanceUnit == unit) {
                            selectedDistanceUnit = unit
                        }
                    }
                } else {
                    ForEach(WeightUnit.allCases) { unit in
                        metricChip(title: unit.name.uppercased(), isSelected: selectedWeightUnit == unit) {
                            selectedWeightUnit = unit
                        }
                    }
                }
            }
        }
        .overlay(horizontalScrollHints)
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summaryTitle)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(summaryValueText)
                    .font(.title)
                    .fontWeight(.bold)
                if let summaryValueUnitText {
                    Text(summaryValueUnitText)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
            Text(summaryDateText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func metricChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
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

    private var currentWindowInterval: DateInterval {
        ExerciseHistoryChartCalculator.currentWindow(for: timeframe, now: anchorDate)
    }

    private var loadedDataInterval: DateInterval {
        // Use the actual loaded interval if available, otherwise fall back to current window
        return actualLoadedInterval ?? currentWindowInterval
    }
    
    private var visibleWindowInterval: DateInterval {
        // Calculate window based on current scroll position for dynamic axis marks and title
        let scrolledAnchor = snappedRangeStart(for: chartScrollPosition)
        return ExerciseHistoryChartCalculator.currentWindow(for: timeframe, now: scrolledAnchor)
    }
    
    private var fullScrollableInterval: DateInterval {
        // Full range that user can scroll through (for axis marks)
        // Ensure start is always before end to avoid crashes
        let start = earliestAllowedWindowStart
        let end = max(latestAllowedDate, start.addingTimeInterval(1))
        return DateInterval(start: start, end: end)
    }
    
    private var latestAllowedDate: Date {
        // Latest date we can scroll to (end of period containing "now"/today)
        // This is independent of anchorDate so you can always scroll back to present
        let nowWindow = ExerciseHistoryChartCalculator.currentWindow(for: timeframe, now: Date())
        return nowWindow.end
    }

    private var visibleDomainLength: TimeInterval {
        ExerciseHistoryChartCalculator.visibleDomainLength(for: timeframe)
    }

    private var chartPoints: [ExerciseHistoryPoint] {
        if metricMode == .cardio {
            return ExerciseHistoryChartCalculator.cardioPoints(
                sessions: loadedSessions,
                interval: loadedDataInterval,
                timeframe: timeframe,
                exerciseId: scope.exerciseId,
                metric: selectedCardioMetric,
                distanceUnit: selectedDistanceUnit
            )
        }
        return ExerciseHistoryChartCalculator.strengthPoints(
            sessions: loadedSessions,
            interval: loadedDataInterval,
            timeframe: timeframe,
            exerciseId: scope.exerciseId,
            metric: selectedStrengthMetric,
            displayUnit: selectedWeightUnit
        )
    }

    private var selectedPoint: ExerciseHistoryPoint? {
        guard let selectedPointId else { return nil }
        return chartPoints.first { $0.id == selectedPointId }
    }

    private var visibleInterval: DateInterval {
        let start = chartScrollPosition
        let end = start.addingTimeInterval(visibleDomainLength)
        return DateInterval(start: start, end: end)
    }

    private var chartYMax: Double {
        let visiblePoints = chartPoints.filter { point in
            point.startDate < visibleInterval.end && point.endDate > visibleInterval.start
        }
        let maxValue = visiblePoints.map(\.value).max() ?? chartPoints.map(\.value).max() ?? 0
        return max(maxValue * 1.15, 1)
    }    
    private var chartXDomain: ClosedRange<Date> {
        let earliest = earliestAllowedWindowStart
        // Allow scrolling through full range including current period and future dates within it
        let latest = latestAllowedDate
        return earliest...latest
    }
    private var barWidth: CGFloat {
        switch timeframe {
        case .week:
            return 14
        case .month:
            return 8
        case .sixMonths:
            return 10
        case .year:
            return 14
        case .fiveYears:
            return 18
        }
    }

    private var summaryTitle: String {
        if selectedPoint != nil {
            return "SELECTED"
        }
        return metricMode == .cardio ? "CARDIO" : "STRENGTH"
    }

    private var summaryValueText: String {
        let value = selectedPoint?.value ?? currentWindowAverageValue
        switch metricMode {
        case .cardio:
            if selectedCardioMetric == .totalDuration || selectedCardioMetric == .averagePace || selectedCardioMetric == .bestPace {
                return SetDisplayFormatter.formatClockDuration(Int(value.rounded()))
            }
            return SetDisplayFormatter.formatDecimal(value)
        case .strength:
            return SetDisplayFormatter.formatDecimal(value)
        }
    }

    private var summaryValueUnitText: String? {
        if metricMode == .cardio {
            switch selectedCardioMetric {
            case .totalDistance:
                return selectedDistanceUnit.rawValue
            case .totalDuration:
                return nil
            case .averagePace, .bestPace:
                return "/\(selectedDistanceUnit.rawValue)"
            }
        }

        switch selectedStrengthMetric {
        case .maxWeight, .averageWeight:
            return selectedWeightUnit.name
        case .totalVolume:
            return "\(selectedWeightUnit.name)-reps"
        case .totalReps, .averageReps:
            return "reps"
        }
    }

    private var summaryDateText: String {
        if let selectedPoint {
            return ExerciseHistoryChartCalculator.selectionLabel(for: selectedPoint, timeframe: timeframe)
        }
        let start = visibleInterval.start.formatted(date: .abbreviated, time: .omitted)
        let end = visibleInterval.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted)
        return "\(start)-\(end)"
    }

    private var emptyStateText: String {
        if visibleSessionCount > 0 {
            return "No metric data in this timeframe. \(visibleSessionCount) session\(visibleSessionCount == 1 ? "" : "s") found."
        }
        return "No data in this timeframe."
    }

    private var visibleSessionCount: Int {
        scopedSessions(in: visibleInterval).count
    }

    private var currentWindowAverageValue: Double {
        let points = chartPoints.filter { point in
            point.startDate >= currentWindowInterval.start && point.startDate < currentWindowInterval.end
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
            return "\(startMonth) \(startDay)-\(endMonth) \(endDay), \(endYear)"
        case .month:
            let monthYearFormatter = DateFormatter()
            monthYearFormatter.locale = Locale.current
            monthYearFormatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
            return monthYearFormatter.string(from: start)
        case .sixMonths:
            let startMonth = monthFormatter.string(from: start)
            let endMonth = monthFormatter.string(from: end)
            let endYear = yearFormatter.string(from: end)
            return "\(startMonth)-\(endMonth) \(endYear)"
        case .year:
            return yearFormatter.string(from: start)
        case .fiveYears:
            let startYear = yearFormatter.string(from: start)
            let endYear = yearFormatter.string(from: end)
            return "\(startYear)-\(endYear)"
        }
    }

    private var isNextDisabled: Bool {
        // Check based on visible window (scroll position), not anchor
        let currentVisible = snappedRangeStart(for: chartScrollPosition)
        let shifted = ExerciseHistoryChartCalculator.shift(anchorDate: currentVisible, timeframe: timeframe, direction: 1)
        return ExerciseHistoryChartCalculator.currentWindow(for: timeframe, now: shifted).start > Date()
    }
    
    private var isPreviousDisabled: Bool {
        // Check based on visible window (scroll position), not anchor
        let currentVisible = snappedRangeStart(for: chartScrollPosition)
        let shifted = ExerciseHistoryChartCalculator.shift(anchorDate: currentVisible, timeframe: timeframe, direction: -1)
        return ExerciseHistoryChartCalculator.currentWindow(for: timeframe, now: shifted).start < earliestAllowedWindowStart
    }

    private var oldestDataDate: Date? {
        let filtered = sessionService.sessions
            .filter { sessionHasDataForCurrentMetric($0) }
            .sorted { $0.timestamp < $1.timestamp }
        return filtered.first?.timestamp
    }

    private var newestDataDate: Date? {
        let filtered = sessionService.sessions
            .filter { sessionHasDataForCurrentMetric($0) }
            .sorted { $0.timestamp < $1.timestamp }
        return filtered.last?.timestamp
    }

    private var earliestAllowedWindowStart: Date {
        guard let oldestDataDate else { return currentWindowInterval.start }
        return ExerciseHistoryChartCalculator.currentWindow(for: timeframe, now: oldestDataDate).start
    }

    private func shiftWindow(direction: Int) {
        // Shift from the visible window (scroll position), not the old anchor
        let currentVisible = snappedRangeStart(for: chartScrollPosition)
        let shifted = ExerciseHistoryChartCalculator.shift(anchorDate: currentVisible, timeframe: timeframe, direction: direction)
        if direction > 0 {
            let shiftedInterval = ExerciseHistoryChartCalculator.currentWindow(for: timeframe, now: shifted)
            guard shiftedInterval.start <= Date() else { return }
        } else {
            // When shifting backward, allow navigation to earlier windows
            let shiftedInterval = ExerciseHistoryChartCalculator.currentWindow(for: timeframe, now: shifted)
            guard shiftedInterval.start >= earliestAllowedWindowStart else { return }
        }
        
        anchorDate = shifted
        
        // When user explicitly shifts window, load the full scrollable range
        // This ensures you can always scroll back/forward after shifting
        let newWindow = ExerciseHistoryChartCalculator.currentWindow(for: timeframe, now: shifted)
        loadedWindows = [newWindow]
        
        // Always load from earliest data to latest allowed date (end of "now" window)
        // This enables smooth bidirectional scrolling regardless of which window you're viewing
        let loadStart = earliestAllowedWindowStart
        let loadEnd = latestAllowedDate
        let loadRange = DateInterval(start: loadStart, end: loadEnd)
        actualLoadedInterval = loadRange
        loadedSessions = sessionService.sessionsInRange(loadRange).filter { session in
            !scopedEntries(in: session).isEmpty
        }
        chartScrollPosition = newWindow.start
        selectedPointId = nil
        selectedXDate = nil
    }

    private func resetToCurrentWindow() {
        let window = currentWindowInterval
        loadedWindows = [window]
        
        // Load data for the entire scrollable range (from earliest data to latest allowed date)
        // This allows free scrolling through all historical data without snapping
        let loadRange = DateInterval(start: earliestAllowedWindowStart, end: latestAllowedDate)
        actualLoadedInterval = loadRange
        loadedSessions = sessionService.sessionsInRange(loadRange).filter { session in
            !scopedEntries(in: session).isEmpty
        }
        chartScrollPosition = window.start
        selectedPointId = nil
        selectedXDate = nil
    }

    private func extendLoadedIntervalIfNeeded(for referenceDate: Date) {
        // Lockout behavior: Don't auto-extend on scroll. Only extend when explicitly 
        // snapping to a new window via shiftWindow() or on first load.
        // This prevents continuous scrolling into old history - user must snap to load it.
        
        guard let first = loadedWindows.first else { return }
        
        // Silently accept (don't extend) if already at earliest allowed window
        if first.start <= earliestAllowedWindowStart {
            return
        }
        
        // For now, don't auto-extend. User must click left arrow to load earlier months.
        // This implements the "lock out if scrolling slowly" requirement.
    }

    private func updateSelectedPoint(for date: Date) {
        guard !chartPoints.isEmpty else {
            selectedPointId = nil
            return
        }
        if let exact = chartPoints.first(where: { date >= $0.startDate && date < $0.endDate && $0.value > 0 }) {
            selectedPointId = exact.id
            return
        }
        selectedPointId = nil
    }

    private func previousWindow(before window: DateInterval) -> DateInterval? {
        let anchor = ExerciseHistoryChartCalculator.shift(anchorDate: window.start, timeframe: timeframe, direction: -1)
        let previous = ExerciseHistoryChartCalculator.currentWindow(for: timeframe, now: anchor)
        if previous.start == window.start {
            return nil
        }
        return previous
    }

    private func snappedRangeStart(for date: Date) -> Date {
        let calendar = Calendar.current
        switch timeframe {
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        case .month:
            return calendar.dateInterval(of: .month, for: date)?.start ?? date
        case .sixMonths:
            return calendar.dateInterval(of: .month, for: date)?.start ?? date
        case .year:
            return calendar.dateInterval(of: .year, for: date)?.start ?? date
        case .fiveYears:
            return calendar.dateInterval(of: .year, for: date)?.start ?? date
        }
    }

    private func sessionHasDataForCurrentMetric(_ session: Session) -> Bool {
        let entries = scopedEntries(in: session)
        guard !entries.isEmpty else { return false }

        switch metricMode {
        case .strength:
            let reps = entries.flatMap(\.sets).flatMap(\.sessionReps)
            switch selectedStrengthMetric {
            case .maxWeight, .averageWeight:
                return reps.contains { $0.weight > 0 }
            case .totalVolume:
                return reps.contains { $0.weight > 0 && $0.count > 0 }
            case .totalReps, .averageReps:
                return reps.contains { $0.count > 0 }
            }
        case .cardio:
            let sets = entries.flatMap(\.sets)
            switch selectedCardioMetric {
            case .totalDistance:
                return sets.contains { ($0.distance ?? 0) > 0 }
            case .totalDuration:
                return sets.contains { ($0.durationSeconds ?? 0) > 0 }
            case .averagePace, .bestPace:
                return sets.contains { set in
                    SetDisplayFormatter.resolvePaceSeconds(
                        explicitPaceSeconds: set.paceSeconds,
                        durationSeconds: set.durationSeconds,
                        distance: set.distance
                    ) != nil
                }
            }
        }
    }

    private func scopedSessions(in interval: DateInterval) -> [Session] {
        sessionService.sessionsInRange(interval).filter { session in
            !scopedEntries(in: session).isEmpty
        }
    }

    private func scopedEntries(in session: Session) -> [SessionEntry] {
        session.sessionEntries.filter { entry in
            guard let scopeExerciseId = scope.exerciseId else { return true }
            return entry.exercise.id == scopeExerciseId
        }
    }

    private var horizontalScrollHints: some View {
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
