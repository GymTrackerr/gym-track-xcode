//
//  ExerciseProgressionViews.swift
//  GymTracker
//
//  Created by Codex on 2026-04-19.
//

import SwiftUI

struct ExerciseProgressionCardView: View {
    let progressionExercise: ProgressionExercise?
    let profile: ProgressionProfile?
    let inheritedProgressionExercise: ProgressionExercise?
    let inheritedProfile: ProgressionProfile?
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Exercise Override")
                        .font(.headline)

                    if let progressionExercise {
                        Text(profile?.miniDescription ?? progressionExercise.progressionMiniDescriptionSnapshot ?? "Saved target guidance for this exercise.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Set an exercise-only override. If you leave this empty, routine, programme, or global defaults can still apply automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    onEdit()
                } label: {
                    Label(progressionExercise == nil ? "Set" : "Edit", systemImage: progressionExercise == nil ? "plus.circle" : "pencil")
                }
                .buttonStyle(.bordered)
            }

            if let progressionExercise {
                detailRow(
                    title: "Profile",
                    value: profile?.name ?? progressionExercise.progressionNameSnapshot ?? "Custom"
                )
                detailRow(
                    title: "Target",
                    value: ProgressionDisplayFormatter.targetSummary(
                        setCount: progressionExercise.targetSetCount,
                        targetReps: progressionExercise.targetReps,
                        targetRepsLow: progressionExercise.targetRepsLow,
                        targetRepsHigh: progressionExercise.targetRepsHigh,
                        weight: progressionExercise.workingWeight,
                        weightLow: progressionExercise.suggestedWeightLow,
                        weightHigh: progressionExercise.suggestedWeightHigh,
                        unit: progressionExercise.workingWeightUnit
                    )
                )

                let cycleSummary = ProgressionDisplayFormatter.targetSummary(
                    setCount: progressionExercise.targetSetCount,
                    targetReps: nil,
                    targetRepsLow: progressionExercise.targetRepsLow,
                    targetRepsHigh: progressionExercise.targetRepsHigh,
                    weight: progressionExercise.workingWeight,
                    weightLow: progressionExercise.suggestedWeightLow,
                    weightHigh: progressionExercise.suggestedWeightHigh,
                    unit: progressionExercise.workingWeightUnit
                )
                detailRow(title: "Cycle", value: cycleSummary)

                if let completedWeightText = ProgressionDisplayFormatter.weightSummary(
                    weight: progressionExercise.lastCompletedCycleWeight,
                    unit: progressionExercise.lastCompletedCycleUnit
                ) {
                    detailRow(
                        title: "Last Top Set",
                        value: "\(completedWeightText) x \(progressionExercise.lastCompletedCycleReps ?? progressionExercise.targetRepsHigh ?? progressionExercise.targetReps ?? 0)"
                    )
                }
            } else if let inheritedProgressionExercise {
                detailRow(
                    title: "Following",
                    value: inheritedProfile?.name ?? inheritedProgressionExercise.progressionNameSnapshot ?? "Automatic progression"
                )
                detailRow(
                    title: "Source",
                    value: inheritedProgressionExercise.assignmentSource.title
                )
            } else {
                Text("No exercise override yet. Routine, programme, or global defaults can still apply automatically when you start logging.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
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

struct ExerciseProgressionSheetView: View {
    @EnvironmentObject private var progressionService: ProgressionService
    @Environment(\.dismiss) private var dismiss

    let exercise: Exercise

    @State private var selectedProfileId: UUID?
    @State private var targetSets: Int = 3
    @State private var targetReps: Int = 10
    @State private var targetRepsLow: Int = 8
    @State private var targetRepsHigh: Int = 10
    @State private var ignoreNextProfileSelectionChange = false

    private var currentAssignment: ProgressionExercise? {
        progressionService.exerciseOverride(for: exercise.id)
    }

    private var inheritedAssignment: ProgressionExercise? {
        guard let progressionExercise = progressionService.progressionExercise(for: exercise.id),
              !progressionExercise.isExplicitOverride else {
            return nil
        }
        return progressionExercise
    }

    private var selectedProfile: ProgressionProfile? {
        progressionService.profiles.first(where: { $0.id == selectedProfileId })
    }

    var body: some View {
        Form {
            Section("Profile") {
                Picker("Progression", selection: $selectedProfileId) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(progressionService.profiles, id: \.id) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }

                if let selectedProfile {
                    Text(selectedProfile.miniDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let selectedProfile {
                Section("Targets") {
                    Stepper("Sets: \(targetSets)", value: $targetSets, in: 1...12)

                    if selectedProfile.type == .doubleProgression {
                        Stepper("Rep Range Low: \(targetRepsLow)", value: $targetRepsLow, in: 1...30)
                        Stepper("Rep Range High: \(targetRepsHigh)", value: $targetRepsHigh, in: 1...30)
                    } else {
                        Stepper("Target Reps: \(targetReps)", value: $targetReps, in: 1...30)
                    }
                }
            }

            if currentAssignment != nil {
                Section {
                    Button("Remove Override", role: .destructive) {
                        progressionService.removeProgression(from: exercise)
                        dismiss()
                    }
                }
            } else if let inheritedAssignment {
                Section("Automatic Source") {
                    Text("\(inheritedAssignment.assignmentSource.title) is currently handling this exercise. Saving here will turn this into an exercise-only override.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Exercise Override")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveAssignment()
                }
                .disabled(selectedProfileId == nil && currentAssignment == nil)
            }
        }
        .onAppear {
            progressionService.ensureBuiltInProfiles()
            progressionService.loadProfiles()
            progressionService.loadProgressionExercises()
            seedFromCurrentAssignment()
        }
        .onChange(of: selectedProfileId) { _, _ in
            if ignoreNextProfileSelectionChange {
                ignoreNextProfileSelectionChange = false
                return
            }
            applyDefaultsFromSelectedProfile()
        }
        .onChange(of: targetRepsLow) { _, newValue in
            if targetRepsHigh < newValue {
                targetRepsHigh = newValue
            }
        }
        .onChange(of: targetRepsHigh) { _, newValue in
            if targetRepsLow > newValue {
                targetRepsLow = newValue
            }
        }
    }

    private func seedFromCurrentAssignment() {
        if let currentAssignment {
            ignoreNextProfileSelectionChange = true
            selectedProfileId = currentAssignment.progressionProfileId
            targetSets = max(currentAssignment.targetSetCount, 1)
            targetReps = currentAssignment.targetReps ?? 10
            targetRepsLow = currentAssignment.targetRepsLow ?? currentAssignment.targetReps ?? 8
            targetRepsHigh = currentAssignment.targetRepsHigh ?? max(targetRepsLow, 10)
            return
        }

        if let inheritedAssignment {
            ignoreNextProfileSelectionChange = true
            selectedProfileId = inheritedAssignment.progressionProfileId
            targetSets = max(inheritedAssignment.targetSetCount, 1)
            targetReps = inheritedAssignment.targetReps ?? 10
            targetRepsLow = inheritedAssignment.targetRepsLow ?? inheritedAssignment.targetReps ?? 8
            targetRepsHigh = inheritedAssignment.targetRepsHigh ?? max(targetRepsLow, 10)
            return
        }

        selectedProfileId = progressionService.profiles.first?.id
        applyDefaultsFromSelectedProfile()
    }

    private func applyDefaultsFromSelectedProfile() {
        guard let selectedProfile else { return }
        targetSets = max(selectedProfile.defaultSetsTarget, 1)
        targetReps = selectedProfile.defaultRepsTarget ?? selectedProfile.defaultRepsLow ?? selectedProfile.defaultRepsHigh ?? 10
        targetRepsLow = selectedProfile.defaultRepsLow ?? min(targetReps, 8)
        targetRepsHigh = selectedProfile.defaultRepsHigh ?? max(targetRepsLow, targetReps)
    }

    private func saveAssignment() {
        guard let selectedProfile else {
            progressionService.removeProgression(from: exercise)
            dismiss()
            return
        }

        let repsTarget = selectedProfile.type == .doubleProgression ? nil : targetReps
        let repsLow = selectedProfile.type == .doubleProgression ? min(targetRepsLow, targetRepsHigh) : nil
        let repsHigh = selectedProfile.type == .doubleProgression ? max(targetRepsLow, targetRepsHigh) : nil

        _ = progressionService.assignProgression(
            to: exercise,
            profile: selectedProfile,
            targetSets: targetSets,
            targetReps: repsTarget,
            targetRepsLow: repsLow,
            targetRepsHigh: repsHigh
        )
        dismiss()
    }
}
