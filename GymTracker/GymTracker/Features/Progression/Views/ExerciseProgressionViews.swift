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
        CardRowContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            LocalizedStringResource(
                                "progression.exerciseOverride.title",
                                defaultValue: "Exercise Override",
                                table: "Progression"
                            )
                        )
                            .font(.headline)

                        if let progressionExercise {
                            progressionDescriptionText(
                                profile: profile,
                                snapshot: progressionExercise.progressionMiniDescriptionSnapshot,
                                fallback: LocalizedStringResource(
                                    "progression.exerciseOverride.savedDescription",
                                    defaultValue: "Saved target guidance for this exercise.",
                                    table: "Progression"
                                )
                            )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(
                                LocalizedStringResource(
                                    "progression.exerciseOverride.emptyDescription",
                                    defaultValue: "Set an exercise-only override. If you leave this empty, routine, programme, or global defaults can still apply automatically.",
                                    table: "Progression"
                                )
                            )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        onEdit()
                    } label: {
                        Label {
                            Text(progressionExercise == nil ? setActionResource : editActionResource)
                        } icon: {
                            Image(systemName: progressionExercise == nil ? "plus.circle" : "pencil")
                        }
                    }
                    .buttonStyle(.bordered)
                }

                if let progressionExercise {
                    detailRow(
                        title: LocalizedStringResource("progression.detail.profile", defaultValue: "Profile", table: "Progression"),
                        value: profileName(
                            profile,
                            snapshot: progressionExercise.progressionNameSnapshot,
                            fallback: String(localized: LocalizedStringResource("progression.value.custom", defaultValue: "Custom", table: "Progression"))
                        )
                    )
                    detailRow(
                        title: LocalizedStringResource("progression.detail.target", defaultValue: "Target", table: "Progression"),
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
                    detailRow(
                        title: LocalizedStringResource("progression.detail.cycle", defaultValue: "Cycle", table: "Progression"),
                        value: cycleSummary
                    )

                    if let completedWeightText = ProgressionDisplayFormatter.weightSummary(
                        weight: progressionExercise.lastCompletedCycleWeight,
                        unit: progressionExercise.lastCompletedCycleUnit
                    ) {
                        detailRow(
                            title: LocalizedStringResource("progression.detail.lastTopSet", defaultValue: "Last Top Set", table: "Progression"),
                            value: "\(completedWeightText) x \(progressionExercise.lastCompletedCycleReps ?? progressionExercise.targetRepsHigh ?? progressionExercise.targetReps ?? 0)"
                        )
                    }
                } else if let inheritedProgressionExercise {
                    detailRow(
                        title: LocalizedStringResource("progression.detail.following", defaultValue: "Following", table: "Progression"),
                        value: profileName(
                            inheritedProfile,
                            snapshot: inheritedProgressionExercise.progressionNameSnapshot,
                            fallback: String(localized: LocalizedStringResource("progression.value.automaticProgression", defaultValue: "Automatic progression", table: "Progression"))
                        )
                    )
                    detailRow(
                        title: LocalizedStringResource("progression.detail.source", defaultValue: "Source", table: "Progression"),
                        value: inheritedProgressionExercise.assignmentSource.title
                    )
                } else {
                    Text(
                        LocalizedStringResource(
                            "progression.exerciseOverride.noOverride",
                            defaultValue: "No exercise override yet. Routine, programme, or global defaults can still apply automatically when you start logging.",
                            table: "Progression"
                        )
                    )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
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

    private var setActionResource: LocalizedStringResource {
        LocalizedStringResource("progression.action.set", defaultValue: "Set", table: "Progression")
    }

    private var editActionResource: LocalizedStringResource {
        LocalizedStringResource("progression.action.edit", defaultValue: "Edit", table: "Progression")
    }

    private func profileName(_ profile: ProgressionProfile?, snapshot: String?, fallback: String) -> String {
        if let profile {
            return profile.isBuiltIn ? profile.type.title : profile.name
        }
        return snapshot ?? fallback
    }

    private func progressionDescriptionText(
        profile: ProgressionProfile?,
        snapshot: String?,
        fallback: LocalizedStringResource
    ) -> Text {
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

        if let profile {
            return Text(verbatim: profile.miniDescription)
        }

        if let snapshot {
            return Text(verbatim: snapshot)
        }

        return Text(fallback)
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
            Section {
                Picker(
                    LocalizedStringResource(
                        "progression.field.progression",
                        defaultValue: "Progression",
                        table: "Progression"
                    ),
                    selection: $selectedProfileId
                ) {
                    Text(
                        LocalizedStringResource(
                            "progression.value.none",
                            defaultValue: "None",
                            table: "Progression"
                        )
                    )
                    .tag(Optional<UUID>.none)
                    ForEach(progressionService.profiles, id: \.id) { profile in
                        profileNameText(profile).tag(Optional(profile.id))
                    }
                }

                if let selectedProfile {
                    profileDescriptionText(selectedProfile)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(
                    LocalizedStringResource(
                        "progression.profileEditor.section.profile",
                        defaultValue: "Profile",
                        table: "Progression"
                    )
                )
            }

            if let selectedProfile {
                Section {
                    Stepper(value: $targetSets, in: 1...12) {
                        Text(
                            LocalizedStringResource(
                                "progression.stepper.sets",
                                defaultValue: "Sets: \(targetSets)",
                                table: "Progression"
                            )
                        )
                    }

                    if selectedProfile.type == .doubleProgression {
                        Stepper(value: $targetRepsLow, in: 1...30) {
                            Text(LocalizedStringResource("progression.stepper.repRangeLow", defaultValue: "Rep Range Low: \(targetRepsLow)", table: "Progression"))
                        }
                        Stepper(value: $targetRepsHigh, in: 1...30) {
                            Text(LocalizedStringResource("progression.stepper.repRangeHigh", defaultValue: "Rep Range High: \(targetRepsHigh)", table: "Progression"))
                        }
                    } else {
                        Stepper(value: $targetReps, in: 1...30) {
                            Text(LocalizedStringResource("progression.stepper.targetReps", defaultValue: "Target Reps: \(targetReps)", table: "Progression"))
                        }
                    }
                } header: {
                    Text(LocalizedStringResource("progression.profileEditor.section.targets", defaultValue: "Targets", table: "Progression"))
                }
            }

            if currentAssignment != nil {
                Section {
                    Button(role: .destructive) {
                        progressionService.removeProgression(from: exercise)
                        dismiss()
                    } label: {
                        Text(
                            LocalizedStringResource(
                                "progression.action.removeOverride",
                                defaultValue: "Remove Override",
                                table: "Progression"
                            )
                        )
                    }
                }
            } else if let inheritedAssignment {
                Section {
                    Text(
                        LocalizedStringResource(
                            "progression.exerciseOverride.automaticSourceDescription",
                            defaultValue: "\(inheritedAssignment.assignmentSource.title) is currently handling this exercise. Saving here will turn this into an exercise-only override.",
                            table: "Progression",
                            comment: "Explains that an inherited progression source will be replaced by an exercise override"
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text(LocalizedStringResource("progression.section.automaticSource", defaultValue: "Automatic Source", table: "Progression"))
                }
            }
        }
        .navigationTitle(Text(LocalizedStringResource("progression.exerciseOverride.title", defaultValue: "Exercise Override", table: "Progression")))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Text(LocalizedStringResource("progression.action.cancel", defaultValue: "Cancel", table: "Progression"))
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    saveAssignment()
                } label: {
                    Text(LocalizedStringResource("progression.action.save", defaultValue: "Save", table: "Progression"))
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

    private func profileNameText(_ profile: ProgressionProfile) -> Text {
        if profile.isBuiltIn {
            return Text(profile.type.titleResource)
        }
        return Text(verbatim: profile.name)
    }

    private func profileDescriptionText(_ profile: ProgressionProfile) -> Text {
        if profile.isBuiltIn {
            switch profile.type {
            case .linear:
                return Text(LocalizedStringResource("progression.builtIn.linear.description", defaultValue: "Increase the load by a small amount after a successful session.", table: "Progression"))
            case .doubleProgression:
                return Text(LocalizedStringResource("progression.builtIn.doubleProgression.description", defaultValue: "Build reps inside a range before moving the weight up.", table: "Progression"))
            case .volume:
                return Text(LocalizedStringResource("progression.builtIn.volume.description", defaultValue: "Add more sets over time while keeping reps steady.", table: "Progression"))
            }
        }
        return Text(verbatim: profile.miniDescription)
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
