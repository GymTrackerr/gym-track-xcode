//
//  ProgressionDisplayFormatter.swift
//  GymTracker
//
//  Created by Codex on 2026-04-19.
//

import Foundation

enum ProgressionDisplayFormatter {
    static func repsSummary(
        targetReps: Int?,
        targetRepsLow: Int?,
        targetRepsHigh: Int?
    ) -> String {
        if let targetReps {
            return "\(targetReps)"
        }

        if let targetRepsLow, let targetRepsHigh {
            return "\(targetRepsLow)-\(targetRepsHigh)"
        }

        if let targetRepsLow {
            return "\(targetRepsLow)"
        }

        if let targetRepsHigh {
            return "\(targetRepsHigh)"
        }

        return "-"
    }

    static func weightSummary(weight: Double?, unit: WeightUnit?) -> String? {
        guard let weight, let unit else { return nil }
        return "\(weight.clean) \(unit.name)"
    }

    static func targetSummary(
        setCount: Int?,
        targetReps: Int?,
        targetRepsLow: Int?,
        targetRepsHigh: Int?,
        weight: Double?,
        unit: WeightUnit?
    ) -> String {
        let sets = max(setCount ?? 0, 1)
        let reps = repsSummary(
            targetReps: targetReps,
            targetRepsLow: targetRepsLow,
            targetRepsHigh: targetRepsHigh
        )

        if let weightText = weightSummary(weight: weight, unit: unit) {
            return "\(sets) x \(reps) @ \(weightText)"
        }

        return "\(sets) x \(reps)"
    }
}

private extension Double {
    var clean: String {
        if self == floor(self) {
            return String(format: "%.0f", self)
        }
        return String(format: "%.1f", self)
    }
}
