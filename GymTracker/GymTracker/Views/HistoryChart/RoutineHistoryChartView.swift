//
//  RoutineHistoryChartView.swift
//  GymTracker
//
//  Created by Codex on 2026-03-10.
//

import SwiftUI

struct RoutineHistoryChartView: View {
    @EnvironmentObject var sessionService: SessionService

    let routine: Routine

    @State private var selectedMetric: RoutineHistoryMetric = .sessionsCompleted
    @State private var selectedWeightUnit: WeightUnit = .lb

    var body: some View {
        HistoryChartView(
            navigationTitle: routine.name,
            filterStateToken: {
                var hasher = Hasher()
                hasher.combine(selectedMetric.rawValue)
                hasher.combine(selectedWeightUnit.rawValue)
                return hasher.finalize()
            }(),
            filterControls: {
                VStack(alignment: .leading, spacing: 10) {
                    metricPicker
                    if selectedMetric.requiresWeightUnit {
                        weightUnitPicker
                    }
                }
            },
            pointsProvider: { interval, timeframe in
                RoutineChartCalculator.routinePoints(
                    routine: routine,
                    sessions: sessionService.sessions,
                    interval: interval,
                    timeframe: timeframe,
                    metric: selectedMetric,
                    weightUnit: selectedWeightUnit
                )
            },
            dataBoundsProvider: {
                let routineSessions = sessionService.sessions.filter { $0.routine?.id == routine.id }
                guard !routineSessions.isEmpty else { return (nil, nil) }
                return (
                    oldest: routineSessions.min(by: { $0.timestamp < $1.timestamp })?.timestamp,
                    newest: routineSessions.max(by: { $0.timestamp < $1.timestamp })?.timestamp
                )
            },
            summaryProvider: { selectedPoint, currentWindowAverage, _ in
                let value = selectedPoint?.value ?? currentWindowAverage
                var unitLabel = selectedMetric.unitLabel
                if selectedMetric.requiresWeightUnit {
                    unitLabel = selectedWeightUnit.name
                }
                return HistoryChartSummary(
                    title: selectedPoint == nil ? "AVG \(selectedMetric.title.uppercased())" : "SELECTED",
                    valueText: valueText(for: value),
                    unitText: unitLabel
                )
            },
            emptyStateTextProvider: { _ in
                "No sessions completed in this timeframe."
            }
        )
    }

    private var metricPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RoutineHistoryMetric.allCases) { metric in
                    HistoryChartChip(title: metric.title, isSelected: selectedMetric == metric) {
                        selectedMetric = metric
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .overlay(HistoryChartHorizontalScrollHints())
    }

    private var weightUnitPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WeightUnit.allCases) { unit in
                    HistoryChartChip(title: unit.name.uppercased(), isSelected: selectedWeightUnit == unit) {
                        selectedWeightUnit = unit
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .overlay(HistoryChartHorizontalScrollHints())
    }

    private func valueText(for value: Double) -> String {
        switch selectedMetric {
        case .totalVolume, .averageVolume:
            return SetDisplayFormatter.formatDecimal(value)
        default:
            return String(Int(value.rounded()))
        }
    }
}
