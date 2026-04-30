//
//  SessionProgressionDetailsView.swift
//  GymTracker
//
//  Created by Codex on 2026-04-19.
//

import SwiftUI

struct SessionProgressionDetailsView: View {
    @EnvironmentObject private var progressionService: ProgressionService

    let sessionEntry: SessionEntry

    @State private var showingEditSheet = false

    private var progressionExercise: ProgressionExercise? {
        progressionService.progressionExercise(for: sessionEntry.exercise.id)
    }

    private var profile: ProgressionProfile? {
        progressionExercise.flatMap { progressionService.profile(for: $0) }
    }

    private var profileName: String {
        profile?.name ??
        progressionExercise?.progressionNameSnapshot ??
        sessionEntry.appliedProgressionNameSnapshot ??
        "No saved progression"
    }

    private var profileDescription: String? {
        profile?.miniDescription ??
        progressionExercise?.progressionMiniDescriptionSnapshot ??
        sessionEntry.appliedProgressionMiniDescriptionSnapshot
    }

    private var sourceLabel: String? {
        progressionExercise?.assignmentSource.title
    }

    private var targetSummary: String {
        ProgressionDisplayFormatter.targetSummary(
            setCount: sessionEntry.appliedTargetSetCount,
            targetReps: sessionEntry.appliedTargetReps,
            targetRepsLow: sessionEntry.appliedTargetRepsLow,
            targetRepsHigh: sessionEntry.appliedTargetRepsHigh,
            weight: sessionEntry.appliedTargetWeight,
            weightLow: sessionEntry.appliedTargetWeightLow,
            weightHigh: sessionEntry.appliedTargetWeightHigh,
            unit: sessionEntry.appliedTargetWeightUnit
        )
    }

    private var currentCycleSummary: String {
        if let cycleSummary = sessionEntry.appliedProgressionCycleSummary,
           !cycleSummary.isEmpty {
            return cycleSummary
        }

        if let progressionExercise {
            return ProgressionDisplayFormatter.targetSummary(
                setCount: progressionExercise.targetSetCount,
                targetReps: progressionExercise.targetReps,
                targetRepsLow: progressionExercise.targetRepsLow,
                targetRepsHigh: progressionExercise.targetRepsHigh,
                weight: progressionExercise.workingWeight,
                weightLow: progressionExercise.suggestedWeightLow,
                weightHigh: progressionExercise.suggestedWeightHigh,
                unit: progressionExercise.workingWeightUnit
            )
        }

        return "No saved cycle yet."
    }

    private var lastTopSetText: String? {
        guard let progressionExercise,
              let weightText = ProgressionDisplayFormatter.weightSummary(
                weight: progressionExercise.lastCompletedCycleWeight,
                unit: progressionExercise.lastCompletedCycleUnit
              ) else {
            return nil
        }

        let reps = progressionExercise.lastCompletedCycleReps ??
            progressionExercise.targetRepsHigh ??
            progressionExercise.targetReps ??
            progressionExercise.targetRepsLow

        if let reps {
            return "\(weightText) x \(reps)"
        }
        return weightText
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(profileName)
                            .font(.title3)
                            .fontWeight(.semibold)

                        if let profileDescription, !profileDescription.isEmpty {
                            Text(profileDescription)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        detailRow(title: "Exercise", value: sessionEntry.exercise.name)
                        if let sourceLabel {
                            detailRow(title: "Source", value: sourceLabel)
                        }
                        detailRow(title: "Target", value: targetSummary)
                    }
                }

                sectionCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Current Cycle")
                            .font(.headline)
                        Text(currentCycleSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let lastTopSetText {
                            detailRow(title: "Last Top Set", value: lastTopSetText)
                        }
                    }
                }

                if sessionEntry.hasProgressionSnapshot {
                    sectionCard {
                        SessionProgressionTargetCardView(sessionEntry: sessionEntry)
                    }
                } else {
                    sectionCard {
                        Text("No progression target was snapped into this session entry yet. Once the exercise is started from a routine, programme, or exercise progression, the targets will show here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .screenContentPadding()
        }
        .navigationTitle("Progression")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    showingEditSheet = true
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            NavigationStack {
                ExerciseProgressionSheetView(exercise: sessionEntry.exercise)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .cardRowContainerStyle()
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
