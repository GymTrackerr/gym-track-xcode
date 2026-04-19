//
//  SessionProgressionTargetCardView.swift
//  GymTracker
//
//  Created by Codex on 2026-04-19.
//

import Foundation
import SwiftUI

struct SessionProgressionTargetCardView: View {
    private struct TargetChecklistRow: Identifiable {
        let id: Int
        let order: Int
        let weight: Double?
        let weightLow: Double?
        let weightHigh: Double?
        let repsTarget: Int?
        let repsLow: Int?
        let repsHigh: Int?

        var autofillReps: Int? {
            repsTarget ?? repsHigh ?? repsLow
        }
    }

    let sessionEntry: SessionEntry
    let onAutofill: () -> Void
    let onApplyRep: (Int) -> Void
    let onApplyWeight: (Double, WeightUnit) -> Void

    private var repOptions: [Int] {
        ProgressionDisplayFormatter.repOptions(
            targetReps: sessionEntry.appliedTargetReps,
            targetRepsLow: sessionEntry.appliedTargetRepsLow,
            targetRepsHigh: sessionEntry.appliedTargetRepsHigh
        )
    }

    private var weightOptions: [Double] {
        ProgressionDisplayFormatter.weightOptions(
            weight: sessionEntry.appliedTargetWeight,
            low: sessionEntry.appliedTargetWeightLow,
            high: sessionEntry.appliedTargetWeightHigh
        )
    }

    private var targetUnit: WeightUnit? {
        sessionEntry.appliedTargetWeightUnit
    }

    private var targetRangeText: String {
        ProgressionDisplayFormatter.targetSummary(
            setCount: sessionEntry.appliedTargetSetCount,
            targetReps: sessionEntry.appliedTargetReps,
            targetRepsLow: sessionEntry.appliedTargetRepsLow,
            targetRepsHigh: sessionEntry.appliedTargetRepsHigh,
            weight: sessionEntry.appliedTargetWeight,
            weightLow: sessionEntry.appliedTargetWeightLow,
            weightHigh: sessionEntry.appliedTargetWeightHigh,
            unit: targetUnit
        )
    }

    private var targetChecklistRows: [TargetChecklistRow] {
        let setCount = max(sessionEntry.appliedTargetSetCount ?? 0, 0)
        guard setCount > 0 else { return [] }

        let hasRepTarget = sessionEntry.appliedTargetReps != nil ||
            sessionEntry.appliedTargetRepsLow != nil ||
            sessionEntry.appliedTargetRepsHigh != nil
        let hasWeightTarget = sessionEntry.appliedTargetWeight != nil ||
            sessionEntry.appliedTargetWeightLow != nil ||
            sessionEntry.appliedTargetWeightHigh != nil
        guard hasRepTarget || hasWeightTarget else { return [] }

        return (0..<setCount).map { index in
            TargetChecklistRow(
                id: index,
                order: index,
                weight: sessionEntry.appliedTargetWeight,
                weightLow: sessionEntry.appliedTargetWeightLow,
                weightHigh: sessionEntry.appliedTargetWeightHigh,
                repsTarget: sessionEntry.appliedTargetReps,
                repsLow: sessionEntry.appliedTargetRepsLow,
                repsHigh: sessionEntry.appliedTargetRepsHigh
            )
        }
    }

    private var targetMeaningfulSets: [SessionSet] {
        let exerciseKind = sessionEntry.exercise.setDisplayKind
        return sessionEntry.sets
            .sorted { $0.order < $1.order }
            .filter { SetDisplayFormatter.isMeaningfulSet($0, exerciseKind: exerciseKind) }
    }

    private var targetCompletionStates: [Bool] {
        targetChecklistRows.map { target in
            guard targetMeaningfulSets.indices.contains(target.order) else { return false }
            let candidateSet = targetMeaningfulSets[target.order]
            return set(candidateSet, matches: target)
        }
    }

    private var targetAttemptedStates: [Bool] {
        targetChecklistRows.map { target in
            targetMeaningfulSets.indices.contains(target.order)
        }
    }

    private var nextSuggestedTargetIndex: Int? {
        targetCompletionStates.firstIndex(of: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sessionEntry.appliedProgressionNameSnapshot ?? "Progression Target")
                        .font(.headline)

                    if let miniDescription = sessionEntry.appliedProgressionMiniDescriptionSnapshot,
                       !miniDescription.isEmpty {
                        Text(miniDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    onAutofill()
                } label: {
                    Label("Use Goal", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.borderedProminent)
            }

            detailRow(title: "Next Target", value: targetRangeText)

            if let cycleSummary = sessionEntry.appliedProgressionCycleSummary,
               !cycleSummary.isEmpty {
                Text(cycleSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !targetChecklistRows.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Per Set Goal")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(targetChecklistRows) { row in
                        checklistRow(row)
                    }
                }
            }

            if !repOptions.isEmpty {
                optionGroup(title: "Tap Reps") {
                    ForEach(repOptions, id: \.self) { reps in
                        Button {
                            onApplyRep(reps)
                        } label: {
                            Text("\(reps)")
                                .font(.caption)
                                .fontWeight(sessionEntry.appliedTargetReps == reps ? .bold : .semibold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(minWidth: 44)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            if let targetUnit, !weightOptions.isEmpty {
                optionGroup(title: "Tap Weight") {
                    ForEach(weightOptions, id: \.self) { weight in
                        Button {
                            onApplyWeight(weight, targetUnit)
                        } label: {
                            Text("\(weight.clean) \(targetUnit.name)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func checklistRow(_ row: TargetChecklistRow) -> some View {
        let isCompleted = targetCompletionStates.indices.contains(row.order) ? targetCompletionStates[row.order] : false
        let isAttempted = targetAttemptedStates.indices.contains(row.order) ? targetAttemptedStates[row.order] : false
        let isMissed = isAttempted && !isCompleted
        let isSuggested = nextSuggestedTargetIndex == row.order

        return Button {
            applyTargetDraftAutofill(row)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isCompleted ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isCompleted ? Color.green : (isMissed ? Color.orange : Color.secondary))

                setBadge(text: "\(row.order + 1)")

                VStack(alignment: .leading, spacing: 4) {
                    Text(targetDescription(for: row))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    if isMissed {
                        Text("Tap to reuse this target")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else if isSuggested && !isCompleted {
                        Text("Next target")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if isCompleted {
                        Text("Completed")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }

                Spacer()
            }
            .padding(12)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isMissed
                            ? Color.orange.opacity(0.45)
                            : (isSuggested && !isCompleted ? Color.green.opacity(0.35) : Color.clear),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func applyTargetDraftAutofill(_ target: TargetChecklistRow) {
        if let reps = target.autofillReps {
            onApplyRep(reps)
        }

        if let targetUnit {
            if let weight = target.weight {
                onApplyWeight(weight, targetUnit)
            } else {
                onAutofill()
            }
        }
    }

    private func set(_ sessionSet: SessionSet, matches target: TargetChecklistRow) -> Bool {
        guard let rep = firstMeaningfulRep(in: sessionSet) else { return false }

        let repsMatch: Bool
        if let exact = target.repsTarget {
            repsMatch = rep.count == exact
        } else if let low = target.repsLow, let high = target.repsHigh {
            repsMatch = rep.count >= low && rep.count <= high
        } else if let high = target.repsHigh {
            repsMatch = rep.count == high
        } else if let low = target.repsLow {
            repsMatch = rep.count == low
        } else {
            repsMatch = true
        }

        let weightMatch: Bool
        if let exact = target.weight {
            let comparisonWeight = convert(rep.weight, from: rep.weightUnit, to: targetUnit ?? rep.weightUnit)
            let targetWeight = convert(exact, from: targetUnit ?? rep.weightUnit, to: targetUnit ?? rep.weightUnit)
            weightMatch = abs(comparisonWeight - targetWeight) < 0.05
        } else if let low = target.weightLow, let high = target.weightHigh {
            let comparisonUnit = targetUnit ?? rep.weightUnit
            let comparisonWeight = convert(rep.weight, from: rep.weightUnit, to: comparisonUnit)
            let lowerBound = min(low, high)
            let upperBound = max(low, high)
            weightMatch = comparisonWeight >= lowerBound - 0.05 && comparisonWeight <= upperBound + 0.05
        } else {
            weightMatch = true
        }

        return repsMatch && weightMatch
    }

    private func firstMeaningfulRep(in sessionSet: SessionSet) -> SessionRep? {
        if let firstMeaningful = sessionSet.sessionReps.first(where: { $0.count > 0 || $0.weight > 0 }) {
            return firstMeaningful
        }
        return sessionSet.sessionReps.first
    }

    private func targetDescription(for target: TargetChecklistRow) -> String {
        let repsText = ProgressionDisplayFormatter.repsSummary(
            targetReps: target.repsTarget,
            targetRepsLow: target.repsLow,
            targetRepsHigh: target.repsHigh
        )

        if let targetUnit {
            if let weightText = ProgressionDisplayFormatter.weightSummary(
                weight: target.weight,
                low: target.weightLow,
                high: target.weightHigh,
                unit: targetUnit
            ) {
                return "\(weightText) x \(repsText)"
            }
        }

        return repsText
    }

    private func convert(_ weight: Double, from source: WeightUnit, to target: WeightUnit) -> Double {
        weight * source.conversion(to: target)
    }

    @ViewBuilder
    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private func optionGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    content()
                }
            }
        }
    }

    @ViewBuilder
    private func setBadge(text: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(0.12))
            Text(text)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .frame(width: 36, height: 28)
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
