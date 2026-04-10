import SwiftUI
import SwiftData

struct DemoSeedView: View {
    private let draftProfileSelectionId = "draft"

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var userService: UserService

    @State private var presets: DemoPresetsBundle?
    @State private var configuration: DemoSeedConfiguration?
    @State private var savedProfiles: [DemoSeedProfile] = []
    @State private var selectedProfileId: String = "draft"
    @State private var sourceSummary: String = "Loading..."
    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("Source Account") {
                Text(sourceSummary)
                    .foregroundStyle(.secondary)
            }

            if let currentConfiguration = configuration, let presets {
                if !savedProfiles.isEmpty {
                    Section("Saved Presets") {
                        Picker("Load Previous", selection: $selectedProfileId) {
                            Text("Current draft").tag(draftProfileSelectionId)
                            ForEach(savedProfiles, id: \.id) { profile in
                                Text(profile.pickerLabel).tag(profile.id.uuidString)
                            }
                        }
                        .onChange(of: selectedProfileId) { _, newValue in
                            applySavedProfile(selection: newValue, presets: presets)
                        }

                        if let lastUsed = savedProfiles.first(where: \.lastRan) {
                            Text("Last used: \(lastUsed.pickerLabel)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Demo Account") {
                    TextField(
                        "Demo account name",
                        text: binding(\.demoUserName, fallback: currentConfiguration.demoUserName)
                    )
                    .textInputAutocapitalization(.words)
                }

                Section("Ranges") {
                    Picker("Health Range", selection: binding(\.healthRange, fallback: presets.healthRanges.first!)) {
                        ForEach(presets.healthRanges) { option in
                            Text(option.label).tag(option)
                        }
                    }

                    Picker("Session Range", selection: binding(\.sessionRange, fallback: presets.sessionRanges.first!)) {
                        ForEach(presets.sessionRanges) { option in
                            Text(option.label).tag(option)
                        }
                    }

                    Picker("Nutrition Range", selection: binding(\.nutritionRange, fallback: presets.nutritionRanges.first!)) {
                        ForEach(presets.nutritionRanges) { option in
                            Text(option.label).tag(option)
                        }
                    }

                    Picker("Noise", selection: binding(\.noise, fallback: presets.noiseLevels.first!)) {
                        ForEach(presets.noiseLevels) { option in
                            Text(option.label).tag(option)
                        }
                    }
                }

                Section("Health Targets") {
                    DemoMetricEditor(
                        title: "Steps",
                        meanLabel: "Target",
                        rangeLabel: "Range",
                        meanSuffix: "",
                        rangeSuffix: "",
                        meanStep: 250,
                        rangeStep: 100,
                        setting: healthBinding(\.steps, fallback: currentConfiguration.healthTargets.steps)
                    )

                    DemoMetricEditor(
                        title: "Active Energy",
                        meanLabel: "Target",
                        rangeLabel: "Range",
                        meanSuffix: " kcal",
                        rangeSuffix: " kcal",
                        meanStep: 25,
                        rangeStep: 10,
                        setting: healthBinding(\.activeEnergyKcal, fallback: currentConfiguration.healthTargets.activeEnergyKcal)
                    )

                    DemoMetricEditor(
                        title: "Exercise",
                        meanLabel: "Target",
                        rangeLabel: "Range",
                        meanSuffix: " min",
                        rangeSuffix: " min",
                        meanStep: 5,
                        rangeStep: 5,
                        setting: healthBinding(\.exerciseMinutes, fallback: currentConfiguration.healthTargets.exerciseMinutes)
                    )

                    DemoMetricEditor(
                        title: "Resting Energy",
                        meanLabel: "Target",
                        rangeLabel: "Range",
                        meanSuffix: " kcal",
                        rangeSuffix: " kcal",
                        meanStep: 25,
                        rangeStep: 10,
                        setting: healthBinding(\.restingEnergyKcal, fallback: currentConfiguration.healthTargets.restingEnergyKcal)
                    )

                    DemoMetricEditor(
                        title: "Sleep",
                        meanLabel: "Target",
                        rangeLabel: "Range",
                        meanSuffix: " h",
                        rangeSuffix: " h",
                        meanStep: 0.25,
                        rangeStep: 0.25,
                        setting: healthBinding(\.sleepHours, fallback: currentConfiguration.healthTargets.sleepHours)
                    )

                    DemoMetricEditor(
                        title: "Body Weight",
                        meanLabel: "Target",
                        rangeLabel: "Range",
                        meanSuffix: " kg",
                        rangeSuffix: " kg",
                        meanStep: 0.5,
                        rangeStep: 0.25,
                        setting: healthBinding(\.bodyWeightKg, fallback: currentConfiguration.healthTargets.bodyWeightKg)
                    )
                }

                Section("Nutrition Targets") {
                    DemoMetricEditor(
                        title: "Calories",
                        meanLabel: "Target",
                        rangeLabel: "Range",
                        meanSuffix: " kcal",
                        rangeSuffix: " kcal",
                        meanStep: 50,
                        rangeStep: 25,
                        setting: healthBinding(\.nutritionCalories, fallback: currentConfiguration.healthTargets.nutritionCalories)
                    )

                    Text(estimatedDeficitRangeText(for: currentConfiguration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Actions") {
                    Button("Enter Demo Mode") {
                        runAction { service in
                            let summary = try service.enterDemoMode(configuration: currentConfiguration)
                            return "Demo mode ready: \(summary.sessionCount) sessions, \(summary.logCount) nutrition logs, \(summary.healthDayCount) health days."
                        }
                    }
                    .disabled(isWorking)

                    Button("Reset Demo Data") {
                        runAction { service in
                            let summary = try service.resetDemoData(configuration: currentConfiguration)
                            return "Demo data rebuilt: \(summary.exerciseCount) exercises, \(summary.routineCount) routines, \(summary.sessionCount) sessions."
                        }
                    }
                    .disabled(isWorking)

                    Button("Exit Demo Mode") {
                        runAction { service in
                            try service.exitDemoMode()
                            return "Returned to your last real account."
                        }
                    }
                    .disabled(isWorking)
                }
            }

            if let statusMessage {
                Section("Status") {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Section("Error") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Demo Mode")
        .task {
            loadPresets()
            reloadDerivedState()
        }
    }

    private func demoService() -> DemoSeedService {
        DemoSeedService(context: modelContext, userService: userService)
    }

    private func loadPresets() {
        do {
            let presets = try DemoTemplateLoader.loadPresets()
            self.presets = presets
            if configuration == nil {
                if let profile = try demoService().lastUsedProfile() {
                    configuration = demoService().configuration(for: profile, presets: presets)
                    selectedProfileId = profile.id.uuidString
                } else {
                    configuration = presets.defaultConfiguration()
                    selectedProfileId = draftProfileSelectionId
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reloadDerivedState() {
        do {
            savedProfiles = try demoService().savedProfiles()
            syncSelectedProfile()
            sourceSummary = try demoService().sourceUserSummary()
        } catch {
            errorMessage = error.localizedDescription
            sourceSummary = error.localizedDescription
        }
    }

    private func runAction(_ work: @escaping (DemoSeedService) throws -> String) {
        isWorking = true
        statusMessage = nil
        errorMessage = nil

        Task { @MainActor in
            defer { isWorking = false }
            do {
                let message = try work(demoService())
                statusMessage = message
                reloadDerivedState()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<DemoSeedConfiguration, T>, fallback: T) -> Binding<T> {
        Binding(
            get: { configuration?[keyPath: keyPath] ?? fallback },
            set: { newValue in
                guard var configuration else { return }
                configuration[keyPath: keyPath] = newValue
                self.configuration = configuration
                selectedProfileId = draftProfileSelectionId
            }
        )
    }

    private func healthBinding(_ keyPath: WritableKeyPath<DemoHealthTargetSettings, DemoMetricTargetSetting>, fallback: DemoMetricTargetSetting) -> Binding<DemoMetricTargetSetting> {
        Binding(
            get: { configuration?.healthTargets[keyPath: keyPath] ?? fallback },
            set: { newValue in
                guard var configuration else { return }
                configuration.healthTargets[keyPath: keyPath] = newValue
                self.configuration = configuration
                selectedProfileId = draftProfileSelectionId
            }
        )
    }

    private func syncSelectedProfile() {
        guard selectedProfileId != draftProfileSelectionId else { return }
        let hasSelectedProfile = savedProfiles.contains { $0.id.uuidString == selectedProfileId }
        if !hasSelectedProfile {
            selectedProfileId = savedProfiles.first(where: \.lastRan)?.id.uuidString ?? draftProfileSelectionId
        }
    }

    private func estimatedDeficitRangeText(for configuration: DemoSeedConfiguration) -> String {
        let activeLow = max(0, configuration.healthTargets.activeEnergyKcal.mean - configuration.healthTargets.activeEnergyKcal.range)
        let activeHigh = configuration.healthTargets.activeEnergyKcal.mean + configuration.healthTargets.activeEnergyKcal.range
        let restLow = max(0, configuration.healthTargets.restingEnergyKcal.mean - configuration.healthTargets.restingEnergyKcal.range)
        let restHigh = configuration.healthTargets.restingEnergyKcal.mean + configuration.healthTargets.restingEnergyKcal.range
        let intakeLow = max(0, configuration.healthTargets.nutritionCalories.mean - configuration.healthTargets.nutritionCalories.range)
        let intakeHigh = configuration.healthTargets.nutritionCalories.mean + configuration.healthTargets.nutritionCalories.range

        let burnLow = Int((activeLow + restLow).rounded())
        let burnHigh = Int((activeHigh + restHigh).rounded())
        let deficitLow = Int(((activeLow + restLow) - intakeHigh).rounded())
        let deficitHigh = Int(((activeHigh + restHigh) - intakeLow).rounded())

        return """
        Burned band: \(burnLow) to \(burnHigh) kcal
        Intake band: \(Int(intakeLow.rounded())) to \(Int(intakeHigh.rounded())) kcal
        Estimated deficit/surplus: \(formattedSigned(deficitLow)) to \(formattedSigned(deficitHigh)) kcal
        """
    }

    private func applySavedProfile(selection: String, presets: DemoPresetsBundle) {
        guard selection != draftProfileSelectionId else { return }
        guard let profile = savedProfiles.first(where: { $0.id.uuidString == selection }) else { return }
        configuration = demoService().configuration(for: profile, presets: presets)
    }

    private func formattedSigned(_ value: Int) -> String {
        let prefix = value >= 0 ? "+" : ""
        return "\(prefix)\(value)"
    }
}

private struct DemoMetricEditor: View {
    let title: String
    let meanLabel: String
    let rangeLabel: String
    let meanSuffix: String
    let rangeSuffix: String
    let meanStep: Double
    let rangeStep: Double
    @Binding var setting: DemoMetricTargetSetting

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            Stepper(value: $setting.mean, in: 0...100_000, step: meanStep) {
                Text("\(meanLabel): \(formatted(setting.mean))\(meanSuffix)")
            }

            Stepper(value: $setting.range, in: 0...100_000, step: rangeStep) {
                Text("\(rangeLabel): \(formatted(setting.range))\(rangeSuffix)")
            }

            Text(rangeHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var rangeHint: String {
        let low = max(0, setting.mean - setting.range)
        let high = setting.mean + setting.range
        return "Generated band: \(formatted(low)) to \(formatted(high))\(meanSuffix)"
    }

    private func formatted(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
}
