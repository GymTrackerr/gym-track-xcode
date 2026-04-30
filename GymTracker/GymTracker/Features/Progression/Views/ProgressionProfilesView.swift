//
//  ProgressionProfilesView.swift
//  GymTracker
//
//  Created by Codex on 2026-04-19.
//

import SwiftUI

struct ProgressionProfilesView: View {
    @EnvironmentObject private var progressionService: ProgressionService

    @State private var showingCreateProfile = false
    @State private var editingProfile: ProgressionProfile?
    @State private var globalProgressionEnabled = false
    @State private var selectedGlobalProfileId: UUID?

    private var builtInProfiles: [ProgressionProfile] {
        progressionService.profiles.filter(\.isBuiltIn)
    }

    private var customProfiles: [ProgressionProfile] {
        progressionService.profiles.filter { !$0.isBuiltIn }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader(
                    title: "Automatic Progression",
                    subtitle: "Enable this if you want every routine-less exercise to fall back to one default profile when no exercise, routine, or programme override is set."
                )

                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable progression for everything", isOn: $globalProgressionEnabled)

                    Picker("Default Profile", selection: $selectedGlobalProfileId) {
                        Text("None").tag(Optional<UUID>.none)
                        ForEach(progressionService.profiles, id: \.id) { profile in
                            Text(profile.name).tag(Optional(profile.id))
                        }
                    }
                    .disabled(!globalProgressionEnabled)

                    Text("Session source still wins first: exercise override, then programme default, then routine default, and this global default fills the gaps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .cardRowContainerStyle()

                sectionHeader(
                    title: "Built-in Progressions",
                    subtitle: "These seed from JSON once, live in the database after that, and can be tuned for your defaults."
                )

                if builtInProfiles.isEmpty {
                    emptyCard("Built-in profiles are still loading.")
                } else {
                    VStack(spacing: 12) {
                        ForEach(builtInProfiles, id: \.id) { profile in
                            profileRow(profile)
                        }
                    }
                }

                sectionHeader(
                    title: "Custom Profiles",
                    subtitle: "Create extra progression setups for exercises that need different targets or increments."
                )

                if customProfiles.isEmpty {
                    emptyCard("No custom profiles yet.")
                } else {
                    VStack(spacing: 12) {
                        ForEach(customProfiles, id: \.id) { profile in
                            profileRow(profile)
                        }
                    }
                }
            }
            .screenContentPadding()
        }
        .navigationTitle("Progression")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreateProfile = true
                } label: {
                    Label("Add Profile", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingCreateProfile) {
            NavigationStack {
                ProgressionProfileEditorSheet(profile: nil)
            }
            .editorSheetPresentation()
        }
        .sheet(item: $editingProfile) { profile in
            NavigationStack {
                ProgressionProfileEditorSheet(profile: profile)
            }
            .editorSheetPresentation()
        }
        .onAppear {
            progressionService.ensureBuiltInProfiles()
            progressionService.loadProfiles()
            seedGlobalDefaults()
        }
        .onChange(of: globalProgressionEnabled) { _, newValue in
            progressionService.saveGlobalDefaults(
                enabled: newValue,
                defaultProfileId: selectedGlobalProfileId
            )
        }
        .onChange(of: selectedGlobalProfileId) { _, newValue in
            progressionService.saveGlobalDefaults(
                enabled: globalProgressionEnabled,
                defaultProfileId: newValue
            )
        }
    }

    private func seedGlobalDefaults() {
        globalProgressionEnabled = progressionService.globalProgressionEnabled
        selectedGlobalProfileId = progressionService.globalDefaultProfileId
    }

    private func profileRow(_ profile: ProgressionProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(.headline)
                    Text(profile.miniDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if profile.isBuiltIn {
                    Text("DEFAULT")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.14))
                        .clipShape(Capsule())
                }
            }

            detailRow(title: "Type", value: profile.type.title)
            detailRow(title: "Default Target", value: defaultTargetSummary(for: profile))
            detailRow(title: "Advancement", value: advancementSummary(for: profile))

            HStack(spacing: 10) {
                Button {
                    editingProfile = profile
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if !profile.isBuiltIn {
                    Button(role: .destructive) {
                        progressionService.delete(profile)
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .cardRowContainerStyle()
    }

    @ViewBuilder
    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func emptyCard(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .cardRowContainerStyle()
    }

    @ViewBuilder
    private func detailRow(title: String, value: String) -> some View {
        HStack {
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

    private func defaultTargetSummary(for profile: ProgressionProfile) -> String {
        ProgressionDisplayFormatter.targetSummary(
            setCount: profile.defaultSetsTarget,
            targetReps: profile.defaultRepsTarget,
            targetRepsLow: profile.defaultRepsLow,
            targetRepsHigh: profile.defaultRepsHigh,
            weight: nil,
            unit: nil
        )
    }

    private func advancementSummary(for profile: ProgressionProfile) -> String {
        let absoluteText = profile.incrementValue > 0 ? "\(profile.incrementValue.clean) \(profile.incrementUnit.name)" : nil
        let percentageText = profile.percentageIncrease > 0 ? "\(profile.percentageIncrease.clean)%" : nil
        let parts = [absoluteText, percentageText].compactMap { $0 }
        return parts.isEmpty ? "Manual" : parts.joined(separator: " + ")
    }
}

private struct ProgressionProfileEditorSheet: View {
    @EnvironmentObject private var progressionService: ProgressionService
    @Environment(\.dismiss) private var dismiss

    let profile: ProgressionProfile?

    @State private var name: String
    @State private var miniDescription: String
    @State private var type: ProgressionType
    @State private var incrementValue: Double
    @State private var percentageIncrease: Double
    @State private var incrementUnit: WeightUnit
    @State private var setIncrement: Int
    @State private var successThreshold: Int
    @State private var defaultSetsTarget: Int
    @State private var defaultRepsTarget: Int
    @State private var defaultRepsLow: Int
    @State private var defaultRepsHigh: Int

    init(profile: ProgressionProfile?) {
        self.profile = profile
        _name = State(initialValue: profile?.name ?? "")
        _miniDescription = State(initialValue: profile?.miniDescription ?? "")
        _type = State(initialValue: profile?.type ?? .linear)
        _incrementValue = State(initialValue: profile?.incrementValue ?? 5)
        _percentageIncrease = State(initialValue: profile?.percentageIncrease ?? 0)
        _incrementUnit = State(initialValue: profile?.incrementUnit ?? .lb)
        _setIncrement = State(initialValue: profile?.setIncrement ?? 1)
        _successThreshold = State(initialValue: profile?.successThreshold ?? 1)
        _defaultSetsTarget = State(initialValue: profile?.defaultSetsTarget ?? 3)
        _defaultRepsTarget = State(initialValue: profile?.defaultRepsTarget ?? 10)
        _defaultRepsLow = State(initialValue: profile?.defaultRepsLow ?? 8)
        _defaultRepsHigh = State(initialValue: profile?.defaultRepsHigh ?? 10)
    }

    var body: some View {
        Form {
            Section("Profile") {
                LabeledContent("Name") {
                    TextField("Required", text: $name)
                        .multilineTextAlignment(.trailing)
                        .disabled(profile?.isBuiltIn == true)
                }

                LabeledContent("Description") {
                    TextField("Mini Description", text: $miniDescription, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .multilineTextAlignment(.trailing)
                }

                Picker("Type", selection: $type) {
                    ForEach(ProgressionType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
            }

            Section("Targets") {
                Stepper("Default Sets: \(defaultSetsTarget)", value: $defaultSetsTarget, in: 1...12)

                if type == .doubleProgression {
                    Stepper("Rep Range Low: \(defaultRepsLow)", value: $defaultRepsLow, in: 1...30)
                    Stepper("Rep Range High: \(defaultRepsHigh)", value: $defaultRepsHigh, in: 1...30)
                } else {
                    Stepper("Target Reps: \(defaultRepsTarget)", value: $defaultRepsTarget, in: 1...30)
                }
            }

            Section("Advancement") {
                LabeledContent("Weight Increment") {
                    TextField("Weight Increment", value: $incrementValue, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }

                LabeledContent("Percentage Increase") {
                    TextField("Percentage Increase", value: $percentageIncrease, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }

                Picker("Increment Unit", selection: $incrementUnit) {
                    ForEach(WeightUnit.allCases) { unit in
                        Text(unit.name).tag(unit)
                    }
                }
                .pickerStyle(.segmented)

                Stepper("Success Threshold: \(successThreshold)", value: $successThreshold, in: 1...10)

                if type == .volume {
                    Stepper("Set Increment: \(setIncrement)", value: $setIncrement, in: 1...5)
                }
            }
        }
        .navigationTitle(profile == nil ? "New Profile" : "Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveProfile()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onChange(of: defaultRepsLow) { _, newValue in
            if defaultRepsHigh < newValue {
                defaultRepsHigh = newValue
            }
        }
        .onChange(of: defaultRepsHigh) { _, newValue in
            if defaultRepsLow > newValue {
                defaultRepsLow = newValue
            }
        }
    }

    private func saveProfile() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = miniDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let repsTarget: Int? = type == .doubleProgression ? nil : max(defaultRepsTarget, 1)
        let repsLow: Int? = type == .doubleProgression ? min(defaultRepsLow, defaultRepsHigh) : nil
        let repsHigh: Int? = type == .doubleProgression ? max(defaultRepsLow, defaultRepsHigh) : nil

        if let profile {
            profile.miniDescription = trimmedDescription
            profile.type = type
            profile.incrementValue = max(incrementValue, 0)
            profile.percentageIncrease = max(percentageIncrease, 0)
            profile.incrementUnit = incrementUnit
            profile.setIncrement = max(setIncrement, 1)
            profile.successThreshold = max(successThreshold, 1)
            profile.defaultSetsTarget = max(defaultSetsTarget, 1)
            profile.defaultRepsTarget = repsTarget
            profile.defaultRepsLow = repsLow
            profile.defaultRepsHigh = repsHigh

            if !profile.isBuiltIn {
                profile.name = trimmedName
            }

            progressionService.saveChanges(for: profile)
        } else {
            _ = progressionService.createProfile(
                name: trimmedName,
                miniDescription: trimmedDescription,
                type: type,
                incrementValue: max(incrementValue, 0),
                percentageIncrease: max(percentageIncrease, 0),
                incrementUnit: incrementUnit,
                setIncrement: max(setIncrement, 1),
                successThreshold: max(successThreshold, 1),
                defaultSetsTarget: max(defaultSetsTarget, 1),
                defaultRepsTarget: repsTarget,
                defaultRepsLow: repsLow,
                defaultRepsHigh: repsHigh
            )
        }

        dismiss()
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
