//
//  ExerciseHistoryChartView.swift
//  GymTracker
//
//  Created by Codex on 2026-02-26.
//

import SwiftUI

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

    @State private var metricMode: ExerciseHistoryMetricMode
    @State private var selectedStrengthMetric: ProgressMetric = .totalVolume
    @State private var selectedCardioMetric: CardioProgressMetric = .totalDistance
    @State private var selectedWeightUnit: WeightUnit = .lb
    @State private var selectedDistanceUnit: DistanceUnit = .km

    init(exercise: Exercise? = nil, exerciseId: UUID? = nil) {
        if let exercise {
            self.scope = .exercise(exercise)
            _metricMode = State(initialValue: exercise.cardio ? .cardio : .strength)
        } else if let exerciseId {
            self.scope = .exerciseId(exerciseId)
            _metricMode = State(initialValue: .strength)
        } else {
            self.scope = .allSessions
            _metricMode = State(initialValue: .strength)
        }
    }

    var body: some View {
        HistoryChartView(
            navigationTitle: scope.title,
            filterStateToken: filterStateToken,
            chartStyle: exerciseChartStyle,
            filterControls: {
                VStack(alignment: .leading, spacing: 10) {
                    modePicker
                    metricPicker
                    unitPicker
                }
            },
            pointsProvider: { interval, timeframe in
                let sessions = scopedSessions(in: interval)
                if metricMode == .cardio {
                    return ExerciseChartCalculator.cardioPoints(
                        sessions: sessions,
                        interval: interval,
                        timeframe: timeframe,
                        exerciseId: scope.exerciseId,
                        metric: selectedCardioMetric,
                        distanceUnit: selectedDistanceUnit
                    )
                }
                return ExerciseChartCalculator.strengthPoints(
                    sessions: sessions,
                    interval: interval,
                    timeframe: timeframe,
                    exerciseId: scope.exerciseId,
                    metric: selectedStrengthMetric,
                    displayUnit: selectedWeightUnit
                )
            },
            dataBoundsProvider: {
                dataBoundsForCurrentMetric()
            },
            summaryProvider: { selectedPoint, currentWindowAverage, _ in
                let value = selectedPoint?.value ?? currentWindowAverage
                return HistoryChartSummary(
                    title: selectedPoint == nil ? (metricMode == .cardio ? "AVG CARDIO" : "AVG STRENGTH") : "SELECTED",
                    valueText: summaryValueText(for: value),
                    unitText: summaryValueUnitText
                )
            },
            emptyStateTextProvider: { _ in
                "No data in this timeframe."
            }
        )
    }

    private var filterStateToken: Int {
        var hasher = Hasher()
        hasher.combine(metricMode.rawValue)
        hasher.combine(selectedStrengthMetric.rawValue)
        hasher.combine(selectedCardioMetric.rawValue)
        hasher.combine(selectedWeightUnit.rawValue)
        hasher.combine(selectedDistanceUnit.rawValue)
        hasher.combine(scope.exerciseId)
        return hasher.finalize()
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
                        HistoryChartChip(title: metric.title, isSelected: selectedCardioMetric == metric) {
                            selectedCardioMetric = metric
                        }
                    }
                } else {
                    ForEach(ProgressMetric.allCases) { metric in
                        HistoryChartChip(title: metric.title, isSelected: selectedStrengthMetric == metric) {
                            selectedStrengthMetric = metric
                        }
                    }
                }
            }
        }
        .overlay(HistoryChartHorizontalScrollHints())
    }

    private var unitPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if metricMode == .cardio {
                    ForEach([DistanceUnit.km, DistanceUnit.mi], id: \.rawValue) { unit in
                        HistoryChartChip(title: unit.rawValue.uppercased(), isSelected: selectedDistanceUnit == unit) {
                            selectedDistanceUnit = unit
                        }
                    }
                } else {
                    ForEach(WeightUnit.allCases) { unit in
                        HistoryChartChip(title: unit.name.uppercased(), isSelected: selectedWeightUnit == unit) {
                            selectedWeightUnit = unit
                        }
                    }
                }
            }
        }
        .overlay(HistoryChartHorizontalScrollHints())
    }

    private func summaryValueText(for value: Double) -> String {
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

    private var exerciseChartStyle: HistoryChartRenderStyle {
        if case .exercise = scope,
           metricMode == .strength,
           selectedStrengthMetric == .averageWeight {
            return .barLine
        }
        return .bar
    }

    private func dataBoundsForCurrentMetric() -> (oldest: Date?, newest: Date?) {
        let filtered = sessionService.sessions
            .filter { sessionHasDataForCurrentMetric($0) }
            .sorted { $0.timestamp < $1.timestamp }

        return (filtered.first?.timestamp, filtered.last?.timestamp)
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
}
