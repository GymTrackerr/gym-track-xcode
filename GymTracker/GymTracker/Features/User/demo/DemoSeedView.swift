import SwiftUI
import SwiftData

struct DemoSeedView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var userService: UserService

    @State private var presets: DemoPresetsBundle?
    @State private var configuration: DemoSeedConfiguration?
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
            refreshSourceSummary()
        }
    }

    private func demoService() -> DemoSeedService {
        DemoSeedService(context: modelContext, userService: userService)
    }

    private func loadPresets() {
        do {
            let presets = try DemoTemplateLoader.loadPresets()
            self.presets = presets
            if configuration == nil,
               let healthRange = presets.healthRanges.first(where: { $0.id == presets.defaultHealthRangeId }) ?? presets.healthRanges.first,
               let sessionRange = presets.sessionRanges.first(where: { $0.id == presets.defaultSessionRangeId }) ?? presets.sessionRanges.first,
               let nutritionRange = presets.nutritionRanges.first(where: { $0.id == presets.defaultNutritionRangeId }) ?? presets.nutritionRanges.first,
               let noise = presets.noiseLevels.first(where: { $0.id == presets.defaultNoiseId }) ?? presets.noiseLevels.first {
                configuration = DemoSeedConfiguration(
                    healthRange: healthRange,
                    sessionRange: sessionRange,
                    nutritionRange: nutritionRange,
                    noise: noise,
                    healthTargets: DemoHealthTargetSettings(presets: presets.defaultTargets)
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshSourceSummary() {
        do {
            sourceSummary = try demoService().sourceUserSummary()
        } catch {
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
                refreshSourceSummary()
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
            }
        )
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
