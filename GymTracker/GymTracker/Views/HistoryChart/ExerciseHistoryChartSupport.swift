//
//  ExerciseHistoryChartSupport.swift
//  GymTracker
//
//  Created by Codex on 2026-02-26.
//

import Foundation

enum ExerciseHistoryTimeframe: String, CaseIterable, Identifiable {
    case week = "W"
    case month = "M"
    case sixMonths = "6M"
    case year = "Y"
    case fiveYears = "5Y"

    var id: String { rawValue }
}

struct ExerciseHistoryPoint: Identifiable {
    let startDate: Date
    let endDate: Date
    let value: Double

    // Unique ID combining start time + duration hash to avoid collisions across buckets
    var id: TimeInterval { 
        startDate.timeIntervalSinceReferenceDate + (endDate.timeIntervalSinceReferenceDate * 0.0001)
    }
    var date: Date { startDate }
}

enum ExerciseHistoryMetricMode: String, CaseIterable, Identifiable {
    case strength = "Strength"
    case cardio = "Cardio"

    var id: String { rawValue }
}

enum ExerciseHistoryChartCalculator {
    static func currentWindow(for timeframe: ExerciseHistoryTimeframe, now: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        switch timeframe {
        case .week:
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
            let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? weekStart.addingTimeInterval(7 * 24 * 3600)
            return DateInterval(start: weekStart, end: weekEnd)
            
        case .month:
            let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
            return DateInterval(start: monthStart, end: monthEnd)
            
        case .sixMonths:
            // Window = 2 months back, 4 months forward (6 months total centered on now)
            let currentMonthStart = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .month, value: -2, to: currentMonthStart) ?? currentMonthStart
            // End 4 months after current month start (so +4 months from now)
            let end = calendar.date(byAdding: .month, value: 4, to: currentMonthStart) ?? currentMonthStart
            return DateInterval(start: start, end: end)
            
        case .year:
            let yearStart = calendar.dateInterval(of: .year, for: now)?.start ?? calendar.startOfDay(for: now)
            let yearEnd = calendar.date(byAdding: .year, value: 1, to: yearStart) ?? yearStart
            return DateInterval(start: yearStart, end: yearEnd)
            
        case .fiveYears:
            // Window = 3 years back, 2 years forward (5 years total centered on now)
            let yearStart = calendar.dateInterval(of: .year, for: now)?.start ?? calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .year, value: -3, to: yearStart) ?? yearStart
            let end = calendar.date(byAdding: .year, value: 2, to: yearStart) ?? yearStart
            return DateInterval(start: start, end: end)
        }
    }

    static func shift(anchorDate: Date, timeframe: ExerciseHistoryTimeframe, direction: Int, calendar: Calendar = .current) -> Date {
        let component: Calendar.Component
        switch timeframe {
        case .week:
            component = .weekOfYear
        case .month:
            component = .month
        case .sixMonths:
            component = .month
        case .year:
            component = .year
        case .fiveYears:
            component = .year
        }
        let amount: Int
        switch timeframe {
        case .sixMonths:
            amount = direction * 6
        case .fiveYears:
            amount = direction * 5
        default:
            amount = direction
        }
        return calendar.date(byAdding: component, value: amount, to: anchorDate) ?? anchorDate
    }

    static func visibleDomainLength(for timeframe: ExerciseHistoryTimeframe) -> TimeInterval {
        let day: TimeInterval = 24 * 60 * 60
        switch timeframe {
        case .week:
            return 7 * day
        case .month:
            return 31 * day
        case .sixMonths:
            return 183 * day
        case .year:
            return 366 * day
        case .fiveYears:
            return 366 * 5 * day
        }
    }

    static func xAxisLabel(for date: Date, timeframe: ExerciseHistoryTimeframe, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current

        switch timeframe {
        case .week:
            formatter.setLocalizedDateFormatFromTemplate("EEE")
            return formatter.string(from: date)
        case .month:
            let day = calendar.component(.day, from: date)
            return String(day)
        case .sixMonths:
            formatter.setLocalizedDateFormatFromTemplate("MMM")
            let text = formatter.string(from: date)
            // Use 3-letter abbreviation for 6-month view
            return String(text.prefix(3))
        case .year:
            formatter.setLocalizedDateFormatFromTemplate("MMM")
            let text = formatter.string(from: date)
            return String(text.prefix(1))
        case .fiveYears:
            formatter.setLocalizedDateFormatFromTemplate("yyyy")
            return formatter.string(from: date)
        }
    }

    static func selectionLabel(for point: ExerciseHistoryPoint, timeframe: ExerciseHistoryTimeframe, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current

        switch timeframe {
        case .week, .month:
            formatter.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
            return formatter.string(from: point.startDate)
        case .sixMonths:
            let start = point.startDate
            let end = calendar.date(byAdding: .day, value: -1, to: point.endDate) ?? point.endDate
            let startMonth = calendar.component(.month, from: start)
            let endMonth = calendar.component(.month, from: end)

            let monthFormatter = DateFormatter()
            monthFormatter.locale = Locale.current
            monthFormatter.setLocalizedDateFormatFromTemplate("MMM")
            let startMonthText = monthFormatter.string(from: start)
            let endMonthText = monthFormatter.string(from: end)
            let startDay = calendar.component(.day, from: start)
            let endDay = calendar.component(.day, from: end)
            if startMonth == endMonth {
                return "\(startMonthText) \(startDay)-\(endDay)"
            }
            return "\(startMonthText) \(startDay)-\(endMonthText) \(endDay)"
        case .year:
            formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
            return formatter.string(from: point.startDate)
        case .fiveYears:
            formatter.setLocalizedDateFormatFromTemplate("yyyy")
            return formatter.string(from: point.startDate)
        }
    }

    static func axisMarkDates(for timeframe: ExerciseHistoryTimeframe, interval: DateInterval, calendar: Calendar = .current) -> [Date]? {
        switch timeframe {
        case .week, .month:
            return nil // Use automatic marks
            
        case .sixMonths:
            // Show monthly markers for 6-month view spanning the full interval
            var marks: [Date] = []
            var cursor = calendar.dateInterval(of: .month, for: interval.start)?.start ?? interval.start
            while cursor < interval.end {
                marks.append(cursor)
                cursor = calendar.date(byAdding: .month, value: 1, to: cursor) ?? interval.end
            }
            return marks
            
        case .year:
            // Show all month marks for year view spanning the full interval
            var marks: [Date] = []
            var cursor = calendar.dateInterval(of: .month, for: interval.start)?.start ?? interval.start
            while cursor < interval.end {
                marks.append(cursor)
                cursor = calendar.date(byAdding: .month, value: 1, to: cursor) ?? interval.end
            }
            return marks
            
        case .fiveYears:
            // Show all year marks for 5-year view spanning the full interval
            var marks: [Date] = []
            var cursor = calendar.dateInterval(of: .year, for: interval.start)?.start ?? interval.start
            while cursor < interval.end {
                marks.append(cursor)
                cursor = calendar.date(byAdding: .year, value: 1, to: cursor) ?? interval.end
            }
            return marks
        }
    }

    static func strengthPoints(
        sessions: [Session],
        interval: DateInterval,
        timeframe: ExerciseHistoryTimeframe,
        exerciseId: UUID?,
        metric: ProgressMetric,
        displayUnit: WeightUnit,
        calendar: Calendar = .current
    ) -> [ExerciseHistoryPoint] {
        let repSamples = strengthSamples(sessions: sessions, interval: interval, exerciseId: exerciseId)
        return bucketIntervals(interval: interval, timeframe: timeframe, calendar: calendar).map { bucket in
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

            return ExerciseHistoryPoint(startDate: bucket.start, endDate: bucket.end, value: value)
        }
    }

    static func cardioPoints(
        sessions: [Session],
        interval: DateInterval,
        timeframe: ExerciseHistoryTimeframe,
        exerciseId: UUID?,
        metric: CardioProgressMetric,
        distanceUnit: DistanceUnit,
        calendar: Calendar = .current
    ) -> [ExerciseHistoryPoint] {
        let samples = cardioSamples(sessions: sessions, interval: interval, exerciseId: exerciseId)
        return bucketIntervals(interval: interval, timeframe: timeframe, calendar: calendar).map { bucket in
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

            return ExerciseHistoryPoint(startDate: bucket.start, endDate: bucket.end, value: value)
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

    private static func bucketIntervals(interval: DateInterval, timeframe: ExerciseHistoryTimeframe, calendar: Calendar) -> [DateInterval] {
        var buckets: [DateInterval] = []
        var cursor = bucketStart(for: interval.start, timeframe: timeframe, calendar: calendar)

        while cursor < interval.end {
            let next = nextBucketStart(after: cursor, timeframe: timeframe, calendar: calendar)
            buckets.append(DateInterval(start: cursor, end: next))
            cursor = next
        }

        return buckets
    }

    private static func bucketStart(for date: Date, timeframe: ExerciseHistoryTimeframe, calendar: Calendar) -> Date {
        switch timeframe {
        case .week, .month:
            return calendar.startOfDay(for: date)
        case .sixMonths:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        case .year:
            return calendar.dateInterval(of: .month, for: date)?.start ?? date
        case .fiveYears:
            return calendar.dateInterval(of: .year, for: date)?.start ?? date
        }
    }

    private static func nextBucketStart(after date: Date, timeframe: ExerciseHistoryTimeframe, calendar: Calendar) -> Date {
        let component: Calendar.Component
        switch timeframe {
        case .week, .month:
            component = .day
        case .sixMonths:
            component = .weekOfYear
        case .year:
            component = .month
        case .fiveYears:
            component = .year
        }
        return calendar.date(byAdding: component, value: 1, to: date) ?? date
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
