import SwiftUI

struct ProgramDayOverrideEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var programService: ProgramService

    @Bindable var overrideModel: ProgramDayExerciseOverride

    @State private var selectedExerciseId: UUID?
    @State private var selectedProgressionId: UUID?

    @State private var setsTargetText: String
    @State private var repsTargetText: String
    @State private var repsLowText: String
    @State private var repsHighText: String
    @State private var orderText: String
    @State private var notesText: String

    init(overrideModel: ProgramDayExerciseOverride) {
        self.overrideModel = overrideModel
        _selectedExerciseId = State(initialValue: overrideModel.exercise?.id)
        _selectedProgressionId = State(initialValue: overrideModel.progression?.id)
        _setsTargetText = State(initialValue: overrideModel.setsTarget.map(String.init) ?? "")
        _repsTargetText = State(initialValue: overrideModel.repsTarget.map(String.init) ?? "")
        _repsLowText = State(initialValue: overrideModel.repsLow.map(String.init) ?? "")
        _repsHighText = State(initialValue: overrideModel.repsHigh.map(String.init) ?? "")
        _orderText = State(initialValue: String(overrideModel.order))
        _notesText = State(initialValue: overrideModel.notes)
    }

    private var exercises: [Exercise] {
        programService.activeExercises()
    }

    private var progressions: [ProgressionProfile] {
        programService.availableProgressionProfiles()
    }

    var body: some View {
        Form {
            Section("Exercise") {
                Picker("Exercise", selection: $selectedExerciseId) {
                    Text("None").tag(UUID?.none)
                    ForEach(exercises, id: \.id) { exercise in
                        Text(exercise.name).tag(Optional(exercise.id))
                    }
                }
            }

            Section("Progression") {
                Picker("Profile", selection: $selectedProgressionId) {
                    Text("None").tag(UUID?.none)
                    ForEach(progressions, id: \.id) { progression in
                        Text(progression.name).tag(Optional(progression.id))
                    }
                }
            }

            Section("Targets") {
                TextField("Sets Target", text: $setsTargetText)
                    .keyboardType(.numberPad)
                TextField("Reps Target", text: $repsTargetText)
                    .keyboardType(.numberPad)
                TextField("Reps Low", text: $repsLowText)
                    .keyboardType(.numberPad)
                TextField("Reps High", text: $repsHighText)
                    .keyboardType(.numberPad)
            }

            Section("Metadata") {
                TextField("Order", text: $orderText)
                    .keyboardType(.numberPad)
                TextField("Notes", text: $notesText, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle("Edit Override")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    saveOverride()
                }
            }
        }
    }

    private func saveOverride() {
        let exercise = exercises.first(where: { $0.id == selectedExerciseId })
        let progression = progressions.first(where: { $0.id == selectedProgressionId })

        _ = programService.updateOverride(
            overrideModel,
            exercise: exercise,
            progression: progression,
            setsTarget: parseOptionalInt(setsTargetText),
            repsTarget: parseOptionalInt(repsTargetText),
            repsLow: parseOptionalInt(repsLowText),
            repsHigh: parseOptionalInt(repsHighText),
            notes: notesText,
            order: parseOptionalInt(orderText) ?? overrideModel.order
        )

        dismiss()
    }

    private func parseOptionalInt(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
    }
}
