//
//  RoutineHistoryChartSupport.swift
//  GymTracker
//
//  Created by Codex on 2026-03-10.
//

import Foundation

enum RoutineHistoryMetric: String, CaseIterable, Identifiable {
    case sessionsCompleted
    case totalExercises
    case averageExercisesPerSession
    case totalVolume
    case totalReps
    case averageVolume
    case averageReps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sessionsCompleted:
            return "Sessions"
        case .totalExercises:
            return "Total Exercises"
        case .averageExercisesPerSession:
            return "Avg Exercises"
        case .totalVolume:
            return "Total Volume"
        case .totalReps:
            return "Total Reps"
        case .averageVolume:
            return "Avg Volume"
        case .averageReps:
            return "Avg Reps"
        }
    }

    var unitLabel: String? {
        switch self {
        case .sessionsCompleted, .totalExercises, .averageExercisesPerSession, .totalReps, .averageReps:
            return nil
        case .totalVolume, .averageVolume:
            return nil // will be set by weight unit
        }
    }
    
    var requiresWeightUnit: Bool {
        switch self {
        case .totalVolume, .averageVolume:
            return true
        default:
            return false
        }
    }
}

enum RoutineChartCalculator {
    static func routinePoints(
        routine: Routine,
        sessions: [Session],
        interval: DateInterval,
        timeframe: HistoryChartTimeframe,
        metric: RoutineHistoryMetric,
        weightUnit: WeightUnit = .lb,
        calendar: Calendar = .current
    ) -> [HistoryChartPoint] {
        let routineSessions = sessions
            .filter { session in
                session.routine?.id == routine.id &&
                session.timestamp >= interval.start &&
                session.timestamp < interval.end
            }
            .sorted { $0.timestamp < $1.timestamp }

        return HistoryChartCalculator.bucketIntervals(interval: interval, timeframe: timeframe, calendar: calendar).map { bucket in
            let sessionsInBucket = routineSessions.filter { $0.timestamp >= bucket.start && $0.timestamp < bucket.end }
            
            let value: Double

            switch metric {
            case .sessionsCompleted:
                value = Double(sessionsInBucket.count)
            case .totalExercises:
                value = Double(sessionsInBucket.flatMap { $0.sessionEntries }.count)
            case .averageExercisesPerSession:
                if sessionsInBucket.isEmpty {
                    value = 0
                } else {
                    let totalExercises = sessionsInBucket.flatMap { $0.sessionEntries }.count
                    value = Double(totalExercises) / Double(sessionsInBucket.count)
                }
            case .totalVolume:
                value = sessionsInBucket.flatMap { $0.sessionEntries }
                    .flatMap { $0.sets }
                    .flatMap { $0.sessionReps }
                    .reduce(0.0) { result, rep in
                        result + (rep.weight * rep.weightUnit.conversion(to: weightUnit) * Double(rep.count))
                    }
            case .totalReps:
                value = Double(sessionsInBucket.flatMap { $0.sessionEntries }
                    .flatMap { $0.sets }
                    .flatMap { $0.sessionReps }
                    .map { $0.count }
                    .reduce(0, +))
            case .averageVolume:
                if sessionsInBucket.isEmpty {
                    value = 0
                } else {
                    let totalVolume = sessionsInBucket.flatMap { $0.sessionEntries }
                        .flatMap { $0.sets }
                        .flatMap { $0.sessionReps }
                        .reduce(0.0) { result, rep in
                            result + (rep.weight * rep.weightUnit.conversion(to: weightUnit) * Double(rep.count))
                        }
                    value = totalVolume / Double(sessionsInBucket.count)
                }
            case .averageReps:
                if sessionsInBucket.isEmpty {
                    value = 0
                } else {
                    let totalReps = sessionsInBucket.flatMap { $0.sessionEntries }
                        .flatMap { $0.sets }
                        .flatMap { $0.sessionReps }
                        .map { $0.count }
                        .reduce(0, +)
                    value = Double(totalReps) / Double(sessionsInBucket.count)
                }
            }

            return HistoryChartPoint(startDate: bucket.start, endDate: bucket.end, value: value)
        }
    }
}
