//
//  SessionProgressionTargetCardView.swift
//  GymTracker
//
//  Created by Codex on 2026-04-19.
//

import SwiftUI

struct SessionProgressionTargetCardView: View {
    let sessionEntry: SessionEntry
    let previousResultText: String?
    let onAutofill: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                    Label("Autofill", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.bordered)
            }

            detailRow(
                title: "Next Target",
                value: ProgressionDisplayFormatter.targetSummary(
                    setCount: sessionEntry.appliedTargetSetCount,
                    targetReps: sessionEntry.appliedTargetReps,
                    targetRepsLow: sessionEntry.appliedTargetRepsLow,
                    targetRepsHigh: sessionEntry.appliedTargetRepsHigh,
                    weight: sessionEntry.appliedTargetWeight,
                    unit: sessionEntry.appliedTargetWeightUnit
                )
            )

            if let previousResultText {
                detailRow(title: "Previous Result", value: previousResultText)
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
}
