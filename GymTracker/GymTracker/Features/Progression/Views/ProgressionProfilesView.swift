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
                SectionHeaderView(
                    resourceTitle: LocalizedStringResource(
                        "progression.profiles.automatic.title",
                        defaultValue: "Automatic Progression",
                        table: "Progression"
                    ),
                    resourceSubtitle: LocalizedStringResource(
                        "progression.profiles.automatic.subtitle",
                        defaultValue: "Enable this if you want every routine-less exercise to fall back to one default profile when no exercise, routine, or programme override is set.",
                        table: "Progression"
                    )
                )

                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $globalProgressionEnabled) {
                        Text(
                            LocalizedStringResource(
                                "progression.profiles.automatic.enable",
                                defaultValue: "Enable progression for everything",
                                table: "Progression"
                            )
                        )
                    }

                    Picker(
                        LocalizedStringResource(
                            "progression.profile.defaultProfile",
                            defaultValue: "Default Profile",
                            table: "Progression"
                        ),
                        selection: $selectedGlobalProfileId
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
                    .disabled(!globalProgressionEnabled)

                    Text(
                        LocalizedStringResource(
                            "progression.profiles.automatic.orderDescription",
                            defaultValue: "Session source still wins first: exercise override, then programme default, then routine default, and this global default fills the gaps.",
                            table: "Progression"
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .cardRowContainerStyle()

                SectionHeaderView(
                    resourceTitle: LocalizedStringResource(
                        "progression.profiles.builtIn.title",
                        defaultValue: "Built-in Progressions",
                        table: "Progression"
                    ),
                    resourceSubtitle: LocalizedStringResource(
                        "progression.profiles.builtIn.subtitle",
                        defaultValue: "These seed from JSON once, live in the database after that, and can be tuned for your defaults.",
                        table: "Progression"
                    )
                )

                if builtInProfiles.isEmpty {
                    emptyCard(
                        LocalizedStringResource(
                            "progression.profiles.builtIn.loading",
                            defaultValue: "Built-in profiles are still loading.",
                            table: "Progression"
                        )
                    )
                } else {
                    VStack(spacing: 12) {
                        ForEach(builtInProfiles, id: \.id) { profile in
                            profileRow(profile)
                        }
                    }
                }

                SectionHeaderView(
                    resourceTitle: LocalizedStringResource(
                        "progression.profiles.custom.title",
                        defaultValue: "Custom Profiles",
                        table: "Progression"
                    ),
                    resourceSubtitle: LocalizedStringResource(
                        "progression.profiles.custom.subtitle",
                        defaultValue: "Create extra progression setups for exercises that need different targets or increments.",
                        table: "Progression"
                    )
                )

                if customProfiles.isEmpty {
                    emptyCard(
                        LocalizedStringResource(
                            "progression.profiles.custom.empty",
                            defaultValue: "No custom profiles yet.",
                            table: "Progression"
                        )
                    )
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
        .navigationTitle(
            Text(
                LocalizedStringResource(
                    "progression.title",
                    defaultValue: "Progression",
                    table: "Progression"
                )
            )
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreateProfile = true
                } label: {
                    Label {
                        Text(
                            LocalizedStringResource(
                                "progression.action.addProfile",
                                defaultValue: "Add Profile",
                                table: "Progression"
                            )
                        )
                    } icon: {
                        Image(systemName: "plus")
                    }
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
                    profileNameText(profile)
                        .font(.headline)
                    profileDescriptionText(profile)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if profile.isBuiltIn {
                    Text(
                        LocalizedStringResource(
                            "progression.badge.default",
                            defaultValue: "DEFAULT",
                            table: "Progression"
                        )
                    )
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.14))
                        .clipShape(Capsule())
                }
            }

            detailRow(
                title: LocalizedStringResource("progression.detail.type", defaultValue: "Type", table: "Progression"),
                value: profile.type.title
            )
            detailRow(
                title: LocalizedStringResource("progression.detail.defaultTarget", defaultValue: "Default Target", table: "Progression"),
                value: defaultTargetSummary(for: profile)
            )
            detailRow(
                title: LocalizedStringResource("progression.detail.advancement", defaultValue: "Advancement", table: "Progression"),
                value: advancementSummary(for: profile)
            )

            HStack(spacing: 10) {
                Button {
                    editingProfile = profile
                } label: {
                    Label {
                        Text(
                            LocalizedStringResource(
                                "progression.action.edit",
                                defaultValue: "Edit",
                                table: "Progression"
                            )
                        )
                    } icon: {
                        Image(systemName: "pencil")
                    }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if !profile.isBuiltIn {
                    Button(role: .destructive) {
                        progressionService.delete(profile)
                    } label: {
                        Label {
                            Text(
                                LocalizedStringResource(
                                    "progression.action.delete",
                                    defaultValue: "Delete",
                                    table: "Progression"
                                )
                            )
                        } icon: {
                            Image(systemName: "trash")
                        }
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .cardRowContainerStyle()
    }

    @ViewBuilder
    private func emptyCard(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .cardRowContainerStyle()
    }

    @ViewBuilder
    private func detailRow(title: LocalizedStringResource, value: String) -> some View {
        HStack {
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
                return Text(
                    LocalizedStringResource(
                        "progression.builtIn.linear.description",
                        defaultValue: "Increase the load by a small amount after a successful session.",
                        table: "Progression"
                    )
                )
            case .doubleProgression:
                return Text(
                    LocalizedStringResource(
                        "progression.builtIn.doubleProgression.description",
                        defaultValue: "Build reps inside a range before moving the weight up.",
                        table: "Progression"
                    )
                )
            case .volume:
                return Text(
                    LocalizedStringResource(
                        "progression.builtIn.volume.description",
                        defaultValue: "Add more sets over time while keeping reps steady.",
                        table: "Progression"
                    )
                )
            }
        }
        return Text(verbatim: profile.miniDescription)
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
        return parts.isEmpty
            ? String(localized: LocalizedStringResource("progression.value.manual", defaultValue: "Manual", table: "Progression"))
            : parts.joined(separator: " + ")
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                profileSection
                targetsSection
                advancementSection
            }
            .screenContentPadding()
        }
        .appBackground()
        .navigationTitle(Text(editorTitleResource))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Text(
                        LocalizedStringResource(
                            "progression.action.cancel",
                            defaultValue: "Cancel",
                            table: "Progression"
                        )
                    )
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    saveProfile()
                } label: {
                    Text(
                        LocalizedStringResource(
                            "progression.action.save",
                            defaultValue: "Save",
                            table: "Progression"
                        )
                    )
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

    private var editorTitleResource: LocalizedStringResource {
        if profile == nil {
            return LocalizedStringResource("progression.profileEditor.newTitle", defaultValue: "New Profile", table: "Progression")
        }
        return LocalizedStringResource("progression.profileEditor.editTitle", defaultValue: "Edit Profile", table: "Progression")
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderView(
                resourceTitle: LocalizedStringResource(
                    "progression.profileEditor.section.profile",
                    defaultValue: "Profile",
                    table: "Progression"
                )
            )
            ConnectedCardSection {
                ConnectedCardRow {
                    LabeledContent {
                        TextField(text: $name, prompt: Text(LocalizedStringResource("progression.placeholder.required", defaultValue: "Required", table: "Progression"))) {
                            Text(LocalizedStringResource("progression.placeholder.required", defaultValue: "Required", table: "Progression"))
                        }
                            .multilineTextAlignment(.trailing)
                            .disabled(profile?.isBuiltIn == true)
                    } label: {
                        Text(
                            LocalizedStringResource(
                                "progression.field.name",
                                defaultValue: "Name",
                                table: "Progression"
                            )
                        )
                    }
                }
                ConnectedCardDivider()
                ConnectedCardRow {
                    LabeledContent {
                        TextField(
                            text: $miniDescription,
                            prompt: Text(
                                LocalizedStringResource(
                                    "progression.placeholder.miniDescription",
                                    defaultValue: "Mini Description",
                                    table: "Progression"
                                )
                            ),
                            axis: .vertical
                        ) {
                            Text(
                                LocalizedStringResource(
                                    "progression.placeholder.miniDescription",
                                    defaultValue: "Mini Description",
                                    table: "Progression"
                                )
                            )
                        }
                            .lineLimit(3, reservesSpace: true)
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Text(
                            LocalizedStringResource(
                                "progression.field.description",
                                defaultValue: "Description",
                                table: "Progression"
                            )
                        )
                    }
                }
                ConnectedCardDivider()
                ConnectedCardRow {
                    Picker(
                        LocalizedStringResource(
                            "progression.field.type",
                            defaultValue: "Type",
                            table: "Progression"
                        ),
                        selection: $type
                    ) {
                        ForEach(ProgressionType.allCases) { type in
                            Text(type.titleResource).tag(type)
                        }
                    }
                }
            }
        }
    }

    private var targetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderView(
                resourceTitle: LocalizedStringResource(
                    "progression.profileEditor.section.targets",
                    defaultValue: "Targets",
                    table: "Progression"
                )
            )
            ConnectedCardSection {
                ConnectedCardRow {
                    Stepper(value: $defaultSetsTarget, in: 1...12) {
                        Text(
                            LocalizedStringResource(
                                "progression.stepper.defaultSets",
                                defaultValue: "Default Sets: \(defaultSetsTarget)",
                                table: "Progression"
                            )
                        )
                    }
                }
                ConnectedCardDivider()
                if type == .doubleProgression {
                    ConnectedCardRow {
                        Stepper(value: $defaultRepsLow, in: 1...30) {
                            Text(
                                LocalizedStringResource(
                                    "progression.stepper.repRangeLow",
                                    defaultValue: "Rep Range Low: \(defaultRepsLow)",
                                    table: "Progression"
                                )
                            )
                        }
                    }
                    ConnectedCardDivider()
                    ConnectedCardRow {
                        Stepper(value: $defaultRepsHigh, in: 1...30) {
                            Text(
                                LocalizedStringResource(
                                    "progression.stepper.repRangeHigh",
                                    defaultValue: "Rep Range High: \(defaultRepsHigh)",
                                    table: "Progression"
                                )
                            )
                        }
                    }
                } else {
                    ConnectedCardRow {
                        Stepper(value: $defaultRepsTarget, in: 1...30) {
                            Text(
                                LocalizedStringResource(
                                    "progression.stepper.targetReps",
                                    defaultValue: "Target Reps: \(defaultRepsTarget)",
                                    table: "Progression"
                                )
                            )
                        }
                    }
                }
            }
        }
    }

    private var advancementSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderView(
                resourceTitle: LocalizedStringResource(
                    "progression.profileEditor.section.advancement",
                    defaultValue: "Advancement",
                    table: "Progression"
                )
            )
            ConnectedCardSection {
                ConnectedCardRow {
                    LabeledContent {
                        TextField(
                            value: $incrementValue,
                            format: .number,
                            prompt: Text(
                                LocalizedStringResource(
                                    "progression.field.weightIncrement",
                                    defaultValue: "Weight Increment",
                                    table: "Progression"
                                )
                            )
                        ) {
                            Text(
                                LocalizedStringResource(
                                    "progression.field.weightIncrement",
                                    defaultValue: "Weight Increment",
                                    table: "Progression"
                                )
                            )
                        }
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Text(
                            LocalizedStringResource(
                                "progression.field.weightIncrement",
                                defaultValue: "Weight Increment",
                                table: "Progression"
                            )
                        )
                    }
                }
                ConnectedCardDivider()
                ConnectedCardRow {
                    LabeledContent {
                        TextField(
                            value: $percentageIncrease,
                            format: .number,
                            prompt: Text(
                                LocalizedStringResource(
                                    "progression.field.percentageIncrease",
                                    defaultValue: "Percentage Increase",
                                    table: "Progression"
                                )
                            )
                        ) {
                            Text(
                                LocalizedStringResource(
                                    "progression.field.percentageIncrease",
                                    defaultValue: "Percentage Increase",
                                    table: "Progression"
                                )
                            )
                        }
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Text(
                            LocalizedStringResource(
                                "progression.field.percentageIncrease",
                                defaultValue: "Percentage Increase",
                                table: "Progression"
                            )
                        )
                    }
                }
                ConnectedCardDivider()
                ConnectedCardRow {
                    Picker(
                        LocalizedStringResource(
                            "progression.field.incrementUnit",
                            defaultValue: "Increment Unit",
                            table: "Progression"
                        ),
                        selection: $incrementUnit
                    ) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit.name).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                ConnectedCardDivider()
                ConnectedCardRow {
                    Stepper(value: $successThreshold, in: 1...10) {
                        Text(
                            LocalizedStringResource(
                                "progression.stepper.successThreshold",
                                defaultValue: "Success Threshold: \(successThreshold)",
                                table: "Progression"
                            )
                        )
                    }
                }
                if type == .volume {
                    ConnectedCardDivider()
                    ConnectedCardRow {
                        Stepper(value: $setIncrement, in: 1...5) {
                            Text(
                                LocalizedStringResource(
                                    "progression.stepper.setIncrement",
                                    defaultValue: "Set Increment: \(setIncrement)",
                                    table: "Progression"
                                )
                            )
                        }
                    }
                }
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
