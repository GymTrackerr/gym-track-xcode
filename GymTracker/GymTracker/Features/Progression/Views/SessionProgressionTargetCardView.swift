//
//  SessionProgressionTargetCardView.swift
//  GymTracker
//
//  Created by Codex on 2026-04-19.
//

import Foundation
import SwiftUI

struct SessionProgressionTargetCardView: View {
    struct TargetAutofillSelection {
        let weight: Double?
        let weightLow: Double?
        let weightHigh: Double?
        let repsTarget: Int?
        let repsLow: Int?
        let repsHigh: Int?
        let weightUnit: WeightUnit?
    }

    private struct TargetChecklistRow: Identifiable {
        let id: Int
        let order: Int
        let weight: Double?
        let weightLow: Double?
        let weightHigh: Double?
        let repsTarget: Int?
        let repsLow: Int?
        let repsHigh: Int?
    }

    private enum TargetStatus {
        case pending
        case under
        case onTarget
        case over
    }

    let sessionEntry: SessionEntry
    let onAutofill: ((TargetAutofillSelection) -> Void)?

    init(
        sessionEntry: SessionEntry,
        onAutofill: ((TargetAutofillSelection) -> Void)? = nil
    ) {
        self.sessionEntry = sessionEntry
        self.onAutofill = onAutofill
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

    private var targetStatuses: [TargetStatus] {
        targetChecklistRows.map { target in
            guard targetMeaningfulSets.indices.contains(target.order) else { return .pending }
            let candidateSet = targetMeaningfulSets[target.order]
            return status(for: candidateSet, target: target)
        }
    }

    private var nextSuggestedTargetIndex: Int? {
        targetStatuses.firstIndex { status in
            status == .pending || status == .under
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Text(
                    LocalizedStringResource(
                        "progression.profileEditor.section.targets",
                        defaultValue: "Targets",
                        table: "Progression"
                    )
                )
                    .font(.headline)

                Spacer()
            }

            targetSummaryRow

            if let cycleSummary = sessionEntry.appliedProgressionCycleSummary,
               !cycleSummary.isEmpty {
                Text(verbatim: cycleSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !targetChecklistRows.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(
                        LocalizedStringResource(
                            "progression.targetCard.perSetGoal",
                            defaultValue: "Per Set Goal",
                            table: "Progression"
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(targetChecklistRows) { row in
                        checklistRow(row)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func checklistRow(_ row: TargetChecklistRow) -> some View {
        let status = targetStatuses.indices.contains(row.order) ? targetStatuses[row.order] : .pending
        let isCompleted = status == .onTarget || status == .over
        let isMissed = status == .under
        let isOver = status == .over
        let isSuggested = nextSuggestedTargetIndex == row.order

        let content = HStack(spacing: 12) {
            Image(systemName: isCompleted ? "checkmark.square.fill" : "square")
                .foregroundStyle(statusColor(for: status))

            setBadge(text: "\(row.order + 1)")

            VStack(alignment: .leading, spacing: 4) {
                Text(targetDescription(for: row))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                if isMissed {
                    Text(
                        LocalizedStringResource(
                            "progression.targetCard.missedTarget",
                            defaultValue: "Missed target on this set",
                            table: "Progression"
                        )
                    )
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else if isOver {
                    Text(
                        LocalizedStringResource(
                            "progression.targetCard.aboveTargetOnSet",
                            defaultValue: "Above target on this set",
                            table: "Progression"
                        )
                    )
                        .font(.caption2)
                        .foregroundStyle(.blue)
                } else if isSuggested && !isCompleted {
                    Text(
                        LocalizedStringResource(
                            "progression.targetCard.nextTarget",
                            defaultValue: "Next target",
                            table: "Progression"
                        )
                    )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if isCompleted {
                    Text(status == .onTarget ? onTargetResource : aboveTargetResource)
                        .font(.caption2)
                        .foregroundStyle(statusColor(for: status))
                }
            }

            Spacer()
        }
        .cardRowContainerStyle()
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isMissed
                        ? Color.orange.opacity(0.45)
                        : (isOver
                            ? Color.blue.opacity(0.4)
                            : (isSuggested && !isCompleted ? Color.green.opacity(0.35) : Color.clear)),
                    lineWidth: 1
                )
        )

        return Group {
            if let onAutofill {
                Button {
                    onAutofill(targetSelection(for: row))
                } label: {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private var targetSummaryRow: some View {
        Group {
            if let onAutofill {
                Button {
                    onAutofill(summarySelection)
                } label: {
                    CardRowContainer {
                        detailRow(
                            title: LocalizedStringResource("progression.targetCard.nextTarget.title", defaultValue: "Next Target", table: "Progression"),
                            value: targetRangeText
                        )
                    }
                }
                .buttonStyle(.plain)
            } else {
                CardRowContainer {
                    detailRow(
                        title: LocalizedStringResource("progression.targetCard.nextTarget.title", defaultValue: "Next Target", table: "Progression"),
                        value: targetRangeText
                    )
                }
            }
        }
    }

    private var onTargetResource: LocalizedStringResource {
        LocalizedStringResource("progression.targetCard.onTarget", defaultValue: "On target", table: "Progression")
    }

    private var aboveTargetResource: LocalizedStringResource {
        LocalizedStringResource("progression.targetCard.aboveTarget", defaultValue: "Above target", table: "Progression")
    }

    private var summarySelection: TargetAutofillSelection {
        TargetAutofillSelection(
            weight: sessionEntry.appliedTargetWeight,
            weightLow: sessionEntry.appliedTargetWeightLow,
            weightHigh: sessionEntry.appliedTargetWeightHigh,
            repsTarget: sessionEntry.appliedTargetReps,
            repsLow: sessionEntry.appliedTargetRepsLow,
            repsHigh: sessionEntry.appliedTargetRepsHigh,
            weightUnit: sessionEntry.appliedTargetWeightUnit
        )
    }

    private func targetSelection(for row: TargetChecklistRow) -> TargetAutofillSelection {
        TargetAutofillSelection(
            weight: row.weight,
            weightLow: row.weightLow,
            weightHigh: row.weightHigh,
            repsTarget: row.repsTarget,
            repsLow: row.repsLow,
            repsHigh: row.repsHigh,
            weightUnit: sessionEntry.appliedTargetWeightUnit
        )
    }

    private func status(for sessionSet: SessionSet, target: TargetChecklistRow) -> TargetStatus {
        guard let rep = firstMeaningfulRep(in: sessionSet) else { return .pending }

        let comparisons = [
            repsStatus(for: rep.count, target: target),
            weightStatus(for: rep, target: target)
        ].compactMap { $0 }

        if comparisons.contains(.under) {
            return .under
        }
        if comparisons.contains(.over) {
            return .over
        }
        if comparisons.contains(.onTarget) {
            return .onTarget
        }
        return .pending
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

    private func repsStatus(for reps: Int, target: TargetChecklistRow) -> TargetStatus? {
        if let exact = target.repsTarget {
            if reps < exact { return .under }
            if reps > exact { return .over }
            return .onTarget
        }

        if let low = target.repsLow, let high = target.repsHigh {
            if reps < low { return .under }
            if reps > high { return .over }
            return .onTarget
        }

        if let high = target.repsHigh {
            if reps < high { return .under }
            if reps > high { return .over }
            return .onTarget
        }

        if let low = target.repsLow {
            if reps < low { return .under }
            if reps > low { return .over }
            return .onTarget
        }

        return nil
    }

    private func weightStatus(for rep: SessionRep, target: TargetChecklistRow) -> TargetStatus? {
        let comparisonUnit = targetUnit ?? rep.weightUnit
        let comparisonWeight = convert(rep.weight, from: rep.weightUnit, to: comparisonUnit)

        if let exact = target.weight {
            if comparisonWeight < exact - 0.05 { return .under }
            if comparisonWeight > exact + 0.05 { return .over }
            return .onTarget
        }

        if let low = target.weightLow, let high = target.weightHigh {
            let lowerBound = min(low, high)
            let upperBound = max(low, high)
            if comparisonWeight < lowerBound - 0.05 { return .under }
            if comparisonWeight > upperBound + 0.05 { return .over }
            return .onTarget
        }

        return nil
    }

    private func statusColor(for status: TargetStatus) -> Color {
        switch status {
        case .pending:
            return .secondary
        case .under:
            return .orange
        case .onTarget:
            return .green
        case .over:
            return .blue
        }
    }

    @ViewBuilder
    private func detailRow(title: LocalizedStringResource, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: value)
                .font(.caption)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
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
