//
//  Set.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import Foundation
import SwiftData
import SwiftUI

// renamed from Set to SessionSet due to reserved keyword
@Model
final class SessionSet {
    var id: UUID = UUID()
    var order: Int
//    var type: Set_Types
    var notes: String?
    var timestamp: Date

    var durationSeconds: Int? = nil
    var distance: Double? = nil
    var paceSeconds: Int? = nil
    var distanceUnitRaw: String? = nil
    var restSeconds: Int? = nil
    
    var isCompleted: Bool = false
    var isDropSet: Bool = false
    
    var sessionEntry: SessionEntry
    var session_entry_id: UUID { sessionEntry.id }

    @Relationship(deleteRule: .cascade)
    var sessionReps: [SessionRep]
    
    init(order: Int, sessionEntry: SessionEntry, notes: String? = nil) {
        self.order = order
        self.notes = notes
        self.timestamp = Date()

        self.sessionEntry = sessionEntry
        self.sessionReps = []
    }

    var distanceUnit: DistanceUnit {
        get { DistanceUnit(rawValue: distanceUnitRaw ?? "km") ?? .km }
        set { distanceUnitRaw = newValue.rawValue }
    }
}

enum DistanceUnit: String, Codable {
    case km
    case mi
}

enum SetDisplayExerciseKind {
    case strength
    case cardio
    case bodyweight
}

struct SetDisplayUnitPreferences {
    var preferredWeightUnit: WeightUnit? = nil
    var preferredDistanceUnit: DistanceUnit? = nil
}

struct SetDisplayChip: Identifiable {
    let id: String
    let text: Text
}

struct SetDisplaySummary {
    let primaryText: Text
    let secondaryText: Text?
    let chips: [SetDisplayChip]
}

enum SetDisplayFormatter {
    static func resolvePaceSeconds(
        explicitPaceSeconds: Int?,
        durationSeconds: Int?,
        distance: Double?
    ) -> Int? {
        if let explicitPaceSeconds, explicitPaceSeconds > 0 {
            return explicitPaceSeconds
        }
        guard let durationSeconds, durationSeconds > 0,
              let distance, distance > 0 else { return nil }
        return Int((Double(durationSeconds) / distance).rounded())
    }

    static func formatClockDuration(_ seconds: Int) -> String {
        let safeSeconds = max(seconds, 0)
        let hours = safeSeconds / 3600
        let minutes = (safeSeconds % 3600) / 60
        let remainingSeconds = safeSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    static func formatPace(
        secondsPerSourceUnit: Int?,
        sourceUnit: DistanceUnit,
        preferredDistanceUnit: DistanceUnit? = nil
    ) -> String? {
        guard let convertedPace = paceSeconds(
            secondsPerSourceUnit: secondsPerSourceUnit,
            sourceUnit: sourceUnit,
            preferredDistanceUnit: preferredDistanceUnit
        ) else { return nil }
        let targetUnit = preferredDistanceUnit ?? sourceUnit
        return "\(formatDuration(convertedPace))/\(targetUnit.rawValue)"
    }

    static func paceSeconds(
        secondsPerSourceUnit: Int?,
        sourceUnit: DistanceUnit,
        preferredDistanceUnit: DistanceUnit? = nil
    ) -> Int? {
        guard let secondsPerSourceUnit, secondsPerSourceUnit > 0 else { return nil }
        let targetUnit = preferredDistanceUnit ?? sourceUnit
        return convertPace(secondsPerSourceUnit, from: sourceUnit, to: targetUnit)
    }

    static func isMeaningfulSet(_ set: SessionSet, exerciseKind: SetDisplayExerciseKind) -> Bool {
        let hasNote = !(set.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        switch exerciseKind {
        case .cardio:
            let hasDuration = (set.durationSeconds ?? 0) > 0
            let hasDistance = (set.distance ?? 0) > 0
            let hasPace = (set.paceSeconds ?? 0) > 0
            return hasDuration || hasDistance || hasPace || hasNote
        case .bodyweight:
            let hasReps = set.sessionReps.contains { $0.count > 0 }
            let hasAddedWeight = set.sessionReps.contains { $0.weight > 0 }
            return hasReps || hasAddedWeight || hasNote
        case .strength:
            let hasReps = set.sessionReps.contains { $0.count > 0 }
            let hasWeight = set.sessionReps.contains { $0.weight > 0 }
            return hasReps || hasWeight || hasNote
        }
    }

    static func formatSetSummary(
        _ set: SessionSet,
        exerciseKind: SetDisplayExerciseKind,
        unitPrefs: SetDisplayUnitPreferences = SetDisplayUnitPreferences()
    ) -> SetDisplaySummary {
        let note = set.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasNote = !(note?.isEmpty ?? true)

        switch exerciseKind {
        case .cardio:
            let durationText = (set.durationSeconds ?? 0) > 0 ? formatDuration(set.durationSeconds ?? 0) : nil
            let distanceText: String?
            if let distance = set.distance, distance > 0 {
                let sourceUnit = set.distanceUnit
                let targetUnit = unitPrefs.preferredDistanceUnit ?? sourceUnit
                let value = convertDistance(distance, from: sourceUnit, to: targetUnit)
                distanceText = "\(formatNumber(value)) \(targetUnit.rawValue)"
            } else {
                distanceText = nil
            }

            let sourceUnit = set.distanceUnit
            let targetUnit = unitPrefs.preferredDistanceUnit ?? sourceUnit
            let paceText = formatPace(
                secondsPerSourceUnit: resolvePaceSeconds(
                    explicitPaceSeconds: set.paceSeconds,
                    durationSeconds: set.durationSeconds,
                    distance: set.distance
                ),
                sourceUnit: sourceUnit,
                preferredDistanceUnit: targetUnit
            ).map { pace in
                Text(
                    LocalizedStringResource(
                        "sessions.set.summary.pace",
                        defaultValue: "Pace \(pace)",
                        table: "Sessions",
                        comment: "Cardio set summary showing pace"
                    )
                )
            }

            let primaryParts = [durationText, distanceText].compactMap { $0 }
            if !primaryParts.isEmpty {
                return SetDisplaySummary(
                    primaryText: Text(verbatim: primaryParts.joined(separator: " • ")),
                    secondaryText: paceText ?? (hasNote ? note.map { Text(verbatim: $0) } : nil),
                    chips: []
                )
            }

            if hasNote {
                return SetDisplaySummary(
                    primaryText: Text(verbatim: note ?? ""),
                    secondaryText: nil,
                    chips: [
                        SetDisplayChip(
                            id: "sessions.set.chip.note",
                            text: Text(
                                LocalizedStringResource(
                                    "sessions.set.chip.note",
                                    defaultValue: "Note",
                                    table: "Sessions"
                                )
                            )
                        )
                    ]
                )
            }

            return SetDisplaySummary(
                primaryText: Text(
                    LocalizedStringResource(
                        "sessions.set.summary.cardioSet",
                        defaultValue: "Cardio set",
                        table: "Sessions"
                    )
                ),
                secondaryText: nil,
                chips: []
            )

        case .bodyweight:
            return formatStrengthLikeSummary(set, kind: .bodyweight, unitPrefs: unitPrefs, note: note)

        case .strength:
            return formatStrengthLikeSummary(set, kind: .strength, unitPrefs: unitPrefs, note: note)
        }
    }

    private static func formatStrengthLikeSummary(
        _ set: SessionSet,
        kind: SetDisplayExerciseKind,
        unitPrefs: SetDisplayUnitPreferences,
        note: String?
    ) -> SetDisplaySummary {
        let reps = set.sessionReps.filter { $0.count > 0 || $0.weight > 0 }

        if reps.isEmpty {
            if let note, !note.isEmpty {
                return SetDisplaySummary(
                    primaryText: Text(verbatim: note),
                    secondaryText: nil,
                    chips: [
                        SetDisplayChip(
                            id: "sessions.set.chip.note",
                            text: Text(
                                LocalizedStringResource(
                                    "sessions.set.chip.note",
                                    defaultValue: "Note",
                                    table: "Sessions"
                                )
                            )
                        )
                    ]
                )
            }
            return SetDisplaySummary(
                primaryText: Text(
                    LocalizedStringResource(
                        "sessions.set.summary.set",
                        defaultValue: "Set",
                        table: "Sessions"
                    )
                ),
                secondaryText: nil,
                chips: []
            )
        }

        let displayRows = reps.prefix(3).map { rep -> String in
            let targetUnit = unitPrefs.preferredWeightUnit ?? rep.weightUnit
            let convertedWeight = rep.weight * rep.weightUnit.conversion(to: targetUnit)
            let hasWeight = convertedWeight > 0
            let hasReps = rep.count > 0

            if kind == .bodyweight {
                if hasReps && hasWeight {
                    return "+\(formatNumber(convertedWeight)) \(targetUnit.name) x \(rep.count)"
                }
                if hasReps {
                    return "\(rep.count) reps"
                }
                return "+\(formatNumber(convertedWeight)) \(targetUnit.name)"
            }

            if hasWeight && hasReps {
                return "\(formatNumber(convertedWeight)) \(targetUnit.name) x \(rep.count)"
            }
            if hasReps {
                return "\(rep.count) reps"
            }
            return "\(formatNumber(convertedWeight)) \(targetUnit.name)"
        }

        var chips: [SetDisplayChip] = []
        if set.isDropSet || reps.count > 1 {
            chips.append(
                SetDisplayChip(
                    id: "sessions.set.chip.dropSet",
                    text: Text(
                        LocalizedStringResource(
                            "sessions.set.chip.dropSet",
                            defaultValue: "Drop Set",
                            table: "Sessions"
                        )
                    )
                )
            )
        }
        if reps.count > 3 {
            chips.append(
                SetDisplayChip(
                    id: "sessions.set.chip.more.\(reps.count - 3)",
                    text: Text(
                        LocalizedStringResource(
                            "sessions.set.chip.more",
                            defaultValue: "+\(reps.count - 3) more",
                            table: "Sessions",
                            comment: "Set summary chip showing additional hidden rows"
                        )
                    )
                )
            )
        }

        return SetDisplaySummary(
            primaryText: Text(verbatim: displayRows.joined(separator: " • ")),
            secondaryText: (note?.isEmpty == false) ? note.map { Text(verbatim: $0) } : nil,
            chips: chips
        )
    }

    // MARK: - Shared Utility Helpers (for views)
    
    static func dominantWeightUnit(in reps: [SessionRep]) -> WeightUnit {
        var counts: [WeightUnit: Int] = [.lb: 0, .kg: 0]
        for rep in reps {
            counts[rep.weightUnit, default: 0] += 1
        }
        return (counts[.kg, default: 0] > counts[.lb, default: 0]) ? .kg : .lb
    }
    
    static func dominantDistanceUnit(in samples: [(distance: Double, unit: DistanceUnit)]) -> DistanceUnit {
        guard !samples.isEmpty else { return .km }
        var counts: [DistanceUnit: Int] = [.km: 0, .mi: 0]
        for sample in samples {
            counts[sample.unit, default: 0] += 1
        }
        return (counts[.mi, default: 0] > counts[.km, default: 0]) ? .mi : .km
    }
    
    static func convertDistance(_ value: Double, from source: DistanceUnit, to target: DistanceUnit) -> Double {
        if source == target { return value }
        if source == .km && target == .mi {
            return value * 0.621371
        }
        return value * 1.60934
    }
    
    static func formatDecimal(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    private static func convertPace(_ secondsPerUnit: Int, from source: DistanceUnit, to target: DistanceUnit) -> Int {
        if source == target { return secondsPerUnit }
        let sourceUnitsPerTargetUnit = convertDistance(1, from: target, to: source)
        let converted = Double(secondsPerUnit) * sourceUnitsPerTargetUnit
        return Int(converted.rounded())
    }

    private static func formatDuration(_ seconds: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: TimeInterval(seconds)) ?? "\(seconds)s"
    }

    private static func formatNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
}

extension Exercise {
    var setDisplayKind: SetDisplayExerciseKind {
        if cardio {
            return .cardio
        }

        if let equipment = equipment?.lowercased(), equipment.contains("body") {
            return .bodyweight
        }

        return .strength
    }
}
