//
//  ExerciseHistoryChartSupport.swift
//  GymTracker
//
//  Created by Codex on 2026-02-26.
//

import Foundation

enum ExerciseHistoryMetricMode: String, CaseIterable, Identifiable {
    case strength = "Strength"
    case cardio = "Cardio"

    var id: String { rawValue }
}

enum ExerciseChartCalculator {
    static func strengthPoints(
        sessions: [Session],
        interval: DateInterval,
        timeframe: HistoryChartTimeframe,
        exerciseId: UUID?,
        metric: ProgressMetric,
        displayUnit: WeightUnit,
        calendar: Calendar = .current
    ) -> [HistoryChartPoint] {
        let repSamples = strengthSamples(sessions: sessions, interval: interval, exerciseId: exerciseId)
        return HistoryChartCalculator.bucketIntervals(interval: interval, timeframe: timeframe, calendar: calendar).map { bucket in
            let items = repSamples.filter { $0.date >= bucket.start && $0.date < bucket.end }
            let value: Double

            switch metric {
            case .maxWeight:
                value = items.map { $0.weight * $0.unit.conversion(to: displayUnit) }.max() ?? 0
            case .averageWeight:
                let total = items.reduce(0.0) { $0 + ($1.weight * $1.unit.conversion(to: displayUnit)) }
                value = items.isEmpty ? 0 : total / Double(items.count)
            case .totalVolume:
                value = items.reduce(0.0) { total, sample in
                    total + (sample.weight * sample.unit.conversion(to: displayUnit) * Double(sample.reps))
                }
            case .totalReps:
                value = Double(items.reduce(0) { $0 + $1.reps })
            case .averageReps:
                let total = items.reduce(0) { $0 + $1.reps }
                value = items.isEmpty ? 0 : Double(total) / Double(items.count)
            }

            return HistoryChartPoint(startDate: bucket.start, endDate: bucket.end, value: value)
        }
    }

    static func cardioPoints(
        sessions: [Session],
        interval: DateInterval,
        timeframe: HistoryChartTimeframe,
        exerciseId: UUID?,
        metric: CardioProgressMetric,
        distanceUnit: DistanceUnit,
        calendar: Calendar = .current
    ) -> [HistoryChartPoint] {
        let samples = cardioSamples(sessions: sessions, interval: interval, exerciseId: exerciseId)
        return HistoryChartCalculator.bucketIntervals(interval: interval, timeframe: timeframe, calendar: calendar).map { bucket in
            let items = samples.filter { $0.date >= bucket.start && $0.date < bucket.end }
            let value: Double

            switch metric {
            case .totalDistance:
                value = items.reduce(0.0) { result, sample in
                    guard let distance = sample.distance else { return result }
                    return result + SetDisplayFormatter.convertDistance(distance, from: sample.distanceUnit, to: distanceUnit)
                }
            case .totalDuration:
                value = Double(items.compactMap(\.durationSeconds).reduce(0, +))
            case .averagePace:
                let paces = items.compactMap {
                    paceValue(for: $0, preferredDistanceUnit: distanceUnit)
                }
                value = paces.isEmpty ? 0 : Double(paces.reduce(0, +)) / Double(paces.count)
            case .bestPace:
                value = Double(items.compactMap {
                    paceValue(for: $0, preferredDistanceUnit: distanceUnit)
                }.min() ?? 0)
            }

            return HistoryChartPoint(startDate: bucket.start, endDate: bucket.end, value: value)
        }
    }

    private struct StrengthSample {
        let date: Date
        let weight: Double
        let unit: WeightUnit
        let reps: Int
    }

    private struct CardioSample {
        let date: Date
        let durationSeconds: Int?
        let distance: Double?
        let distanceUnit: DistanceUnit
        let paceSeconds: Int?
    }

    private static func strengthSamples(sessions: [Session], interval: DateInterval, exerciseId: UUID?) -> [StrengthSample] {
        sessions
            .filter { interval.intersects(DateInterval(start: $0.timestamp, end: $0.timestamp.addingTimeInterval(1))) }
            .flatMap { session in
                session.sessionEntries
                    .filter { entry in
                        guard let exerciseId else { return true }
                        return entry.exercise.id == exerciseId
                    }
                    .flatMap(\.sets)
                    .flatMap(\.sessionReps)
                    .map { rep in
                        StrengthSample(
                            date: session.timestamp,
                            weight: rep.weight,
                            unit: rep.weightUnit,
                            reps: rep.count
                        )
                    }
            }
    }

    private static func cardioSamples(sessions: [Session], interval: DateInterval, exerciseId: UUID?) -> [CardioSample] {
        sessions
            .filter { interval.intersects(DateInterval(start: $0.timestamp, end: $0.timestamp.addingTimeInterval(1))) }
            .flatMap { session in
                session.sessionEntries
                    .filter { entry in
                        guard let exerciseId else { return true }
                        return entry.exercise.id == exerciseId
                    }
                    .flatMap(\.sets)
                    .filter { set in
                        (set.durationSeconds ?? 0) > 0 || (set.distance ?? 0) > 0 || (set.paceSeconds ?? 0) > 0
                    }
                    .map { set in
                        CardioSample(
                            date: session.timestamp,
                            durationSeconds: set.durationSeconds,
                            distance: set.distance,
                            distanceUnit: set.distanceUnit,
                            paceSeconds: set.paceSeconds
                        )
                    }
            }
    }

    private static func paceValue(for sample: CardioSample, preferredDistanceUnit: DistanceUnit) -> Int? {
        let resolvedPace = SetDisplayFormatter.resolvePaceSeconds(
            explicitPaceSeconds: sample.paceSeconds,
            durationSeconds: sample.durationSeconds,
            distance: sample.distance
        )
        return SetDisplayFormatter.paceSeconds(
            secondsPerSourceUnit: resolvedPace,
            sourceUnit: sample.distanceUnit,
            preferredDistanceUnit: preferredDistanceUnit
        )
    }
}
