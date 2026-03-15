import SwiftUI

struct ExerciseProgressionDefaultEditorView: View {
    @EnvironmentObject var progressionDefaultsService: ProgressionDefaultsService

    @Bindable var exercise: Exercise

    @State private var formState = ProgressionDefaultsFormState()

    private var profiles: [ProgressionProfile] {
        progressionDefaultsService.availableProfiles()
    }

    var body: some View {
        Form {
            Section {
                Text(exercise.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ProgressionDefaultsFormSection(
                title: "Exercise Default",
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
        .navigationTitle("Exercise Progression")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadFromModel()
        }
    }

    private func loadFromModel() {
        guard let model = progressionDefaultsService.currentExerciseDefault(for: exercise) else {
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

        _ = progressionDefaultsService.upsertExerciseDefault(
            for: exercise,
            progression: progression,
            setsTarget: parsed.setsTarget,
            repsTarget: parsed.repsTarget,
            repsLow: parsed.repsLow,
            repsHigh: parsed.repsHigh
        )
        loadFromModel()
    }

    private func clear() {
        _ = progressionDefaultsService.removeExerciseDefault(for: exercise)
        loadFromModel()
    }
}
