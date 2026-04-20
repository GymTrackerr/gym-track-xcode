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

    static func weightSummary(
        weight: Double?,
        low: Double?,
        high: Double?,
        unit: WeightUnit?
    ) -> String? {
        if let weight, let unit {
            return weightSummary(weight: weight, unit: unit)
        }

        guard let unit else { return nil }
        let resolvedLow = low ?? high
        let resolvedHigh = high ?? low

        guard let resolvedLow, let resolvedHigh else { return nil }
        if resolvedLow == resolvedHigh {
            return weightSummary(weight: resolvedLow, unit: unit)
        }

        return "\(resolvedLow.clean)-\(resolvedHigh.clean) \(unit.name)"
    }

    static func repOptions(
        targetReps: Int?,
        targetRepsLow: Int?,
        targetRepsHigh: Int?
    ) -> [Int] {
        if let targetRepsLow, let targetRepsHigh, targetRepsLow <= targetRepsHigh {
            return Array(targetRepsLow...targetRepsHigh)
        }

        if let targetReps {
            return [targetReps]
        }

        if let targetRepsLow {
            return [targetRepsLow]
        }

        if let targetRepsHigh {
            return [targetRepsHigh]
        }

        return []
    }

    static func weightOptions(
        weight: Double?,
        low: Double?,
        high: Double?
    ) -> [Double] {
        if let weight {
            return [weight]
        }

        let resolvedLow = low ?? high
        let resolvedHigh = high ?? low

        guard let resolvedLow, let resolvedHigh else { return [] }
        if resolvedLow == resolvedHigh {
            return [resolvedLow]
        }
        return [min(resolvedLow, resolvedHigh), max(resolvedLow, resolvedHigh)]
    }

    static func targetSummary(
        setCount: Int?,
        targetReps: Int?,
        targetRepsLow: Int?,
        targetRepsHigh: Int?,
        weight: Double?,
        weightLow: Double? = nil,
        weightHigh: Double? = nil,
        unit: WeightUnit?
    ) -> String {
        let sets = max(setCount ?? 0, 1)
        let reps = repsSummary(
            targetReps: targetReps,
            targetRepsLow: targetRepsLow,
            targetRepsHigh: targetRepsHigh
        )

        if let weightText = weightSummary(weight: weight, low: weightLow, high: weightHigh, unit: unit) {
            return "\(sets) x \(reps) @ \(weightText)"
        }

        return "\(sets) x \(reps)"
    }

    static func setRangeSummary(setCount: Int?, targetRepsLow: Int?, targetRepsHigh: Int?) -> String {
        let resolvedSets = max(setCount ?? 0, 1)
        let repText = repsSummary(targetReps: nil, targetRepsLow: targetRepsLow, targetRepsHigh: targetRepsHigh)
        return Array(repeating: repText, count: resolvedSets).joined(separator: " • ")
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
