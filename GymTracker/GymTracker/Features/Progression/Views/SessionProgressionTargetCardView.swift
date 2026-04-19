//
//  SessionProgressionTargetCardView.swift
//  GymTracker
//
//  Created by Codex on 2026-04-19.
//

import Foundation
import SwiftUI

struct SessionProgressionTargetCardView: View {
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

    private var setRangeLabels: [String] {
        let setCount = max(sessionEntry.appliedTargetSetCount ?? 0, 1)
        let repText = ProgressionDisplayFormatter.repsSummary(
            targetReps: sessionEntry.appliedTargetReps,
            targetRepsLow: sessionEntry.appliedTargetRepsLow,
            targetRepsHigh: sessionEntry.appliedTargetRepsHigh
        )
        return (0..<setCount).map { "Set \($0 + 1)  \(repText)" }
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

            if !setRangeLabels.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Per Set Range")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(setRangeLabels, id: \.self) { label in
                                Text(label)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color.gray.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
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
}

private extension Double {
    var clean: String {
        if self == floor(self) {
            return String(format: "%.0f", self)
        }
        return String(format: "%.1f", self)
    }
}
