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
        String(localized: LocalizedStringResource("progression.value.noSavedProgression", defaultValue: "No saved progression", table: "Progression"))
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

        return String(localized: LocalizedStringResource("progression.value.noSavedCycle", defaultValue: "No saved cycle yet.", table: "Progression"))
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
                        profileNameText
                            .font(.title3)
                            .fontWeight(.semibold)

                        if let profileDescriptionText {
                            profileDescriptionText
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        detailRow(
                            title: LocalizedStringResource("progression.detail.exercise", defaultValue: "Exercise", table: "Progression"),
                            value: sessionEntry.exercise.name
                        )
                        if let sourceLabel {
                            detailRow(
                                title: LocalizedStringResource("progression.detail.source", defaultValue: "Source", table: "Progression"),
                                value: sourceLabel
                            )
                        }
                        detailRow(
                            title: LocalizedStringResource("progression.detail.target", defaultValue: "Target", table: "Progression"),
                            value: targetSummary
                        )
                    }
                }

                sectionCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(
                            LocalizedStringResource(
                                "progression.sessionDetails.currentCycle",
                                defaultValue: "Current Cycle",
                                table: "Progression"
                            )
                        )
                            .font(.headline)
                        Text(verbatim: currentCycleSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let lastTopSetText {
                            detailRow(
                                title: LocalizedStringResource("progression.detail.lastTopSet", defaultValue: "Last Top Set", table: "Progression"),
                                value: lastTopSetText
                            )
                        }
                    }
                }

                if sessionEntry.hasProgressionSnapshot {
                    sectionCard {
                        SessionProgressionTargetCardView(sessionEntry: sessionEntry)
                    }
                } else {
                    sectionCard {
                        Text(
                            LocalizedStringResource(
                                "progression.sessionDetails.noSnapshot",
                                defaultValue: "No progression target was snapped into this session entry yet. Once the exercise is started from a routine, programme, or exercise progression, the targets will show here.",
                                table: "Progression"
                            )
                        )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .screenContentPadding()
        }
        .navigationTitle(Text(LocalizedStringResource("progression.title", defaultValue: "Progression", table: "Progression")))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEditSheet = true
                } label: {
                    Text(LocalizedStringResource("progression.action.edit", defaultValue: "Edit", table: "Progression"))
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            NavigationStack {
                ExerciseProgressionSheetView(exercise: sessionEntry.exercise)
            }
            .editorSheetPresentation()
        }
    }

    private var profileNameText: Text {
        if let profile, profile.isBuiltIn {
            return Text(profile.type.titleResource)
        }
        return Text(verbatim: profileName)
    }

    private var profileDescriptionText: Text? {
        if let profile, profile.isBuiltIn {
            switch profile.type {
            case .linear:
                return Text(LocalizedStringResource("progression.builtIn.linear.description", defaultValue: "Increase the load by a small amount after a successful session.", table: "Progression"))
            case .doubleProgression:
                return Text(LocalizedStringResource("progression.builtIn.doubleProgression.description", defaultValue: "Build reps inside a range before moving the weight up.", table: "Progression"))
            case .volume:
                return Text(LocalizedStringResource("progression.builtIn.volume.description", defaultValue: "Add more sets over time while keeping reps steady.", table: "Progression"))
            }
        }

        guard let profileDescription, !profileDescription.isEmpty else { return nil }
        return Text(verbatim: profileDescription)
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .cardRowContainerStyle()
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
}
