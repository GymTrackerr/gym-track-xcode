import SwiftUI

struct ProgressionDefaultsSettingsView: View {
    @EnvironmentObject var progressionDefaultsService: ProgressionDefaultsService

    @State private var formState = ProgressionDefaultsFormState()

    private var profiles: [ProgressionProfile] {
        progressionDefaultsService.availableProfiles()
    }

    var body: some View {
        Form {
            ProgressionDefaultsFormSection(
                title: "Global Default",
                formState: $formState,
                profiles: profiles
            )

            Section {
                Button("Save Default") {
                    save()
                }
                Button("Clear Default", role: .destructive) {
                    clear()
                }
            }
        }
        .navigationTitle("Progression Defaults")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadFromModel()
        }
    }

    private func loadFromModel() {
        guard let model = progressionDefaultsService.currentUserDefault() else {
            formState.setValues(
                progressionId: nil,
                setsTarget: nil,
                repsTarget: nil,
                repsLow: nil,
                repsHigh: nil
            )
            return
        }

        formState.setValues(
            progressionId: model.progression?.id,
            setsTarget: model.setsTarget,
            repsTarget: model.repsTarget,
            repsLow: model.repsLow,
            repsHigh: model.repsHigh
        )
    }

    private func save() {
        let progression = profiles.first(where: { $0.id == formState.selectedProgressionId })
        let parsed = formState.parsed

        _ = progressionDefaultsService.upsertUserDefault(
            progression: progression,
            setsTarget: parsed.setsTarget,
            repsTarget: parsed.repsTarget,
            repsLow: parsed.repsLow,
            repsHigh: parsed.repsHigh
        )
        loadFromModel()
    }

    private func clear() {
        _ = progressionDefaultsService.removeUserDefault()
        loadFromModel()
    }
}
