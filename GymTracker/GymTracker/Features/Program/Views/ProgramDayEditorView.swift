import SwiftUI

struct ProgramDayEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var programService: ProgramService

    @Bindable var programDay: ProgramDay
    @State private var openedOverride: ProgramDayExerciseOverride?

    @State private var titleText: String
    @State private var weekNumberText: String
    @State private var selectedWeekday: Int
    @State private var selectedRoutineId: UUID?

    init(programDay: ProgramDay) {
        self.programDay = programDay
        _titleText = State(initialValue: programDay.title)
        _weekNumberText = State(initialValue: String(programDay.weekIndex + 1))
        _selectedWeekday = State(initialValue: programDay.dayIndex)
        _selectedRoutineId = State(initialValue: programDay.routine?.id)
    }

    private var routines: [Routine] {
        programService.activeRoutines()
    }

    private var sortedOverrides: [ProgramDayExerciseOverride] {
        programDay.exerciseOverrides.sorted { $0.order < $1.order }
    }

    var body: some View {
        List {
            Section("Workout") {
                TextField("Title", text: $titleText)
                TextField("Week Number", text: $weekNumberText)
                    .keyboardType(.numberPad)
                Picker("Weekday", selection: $selectedWeekday) {
                    Text("Sunday").tag(0)
                    Text("Monday").tag(1)
                    Text("Tuesday").tag(2)
                    Text("Wednesday").tag(3)
                    Text("Thursday").tag(4)
                    Text("Friday").tag(5)
                    Text("Saturday").tag(6)
                }

                Picker("Routine", selection: $selectedRoutineId) {
                    Text("None").tag(UUID?.none)
                    ForEach(routines, id: \.id) { routine in
                        Text(routine.name).tag(Optional(routine.id))
                    }
                }
            }

            Section("Exercise Overrides") {
                ForEach(sortedOverrides, id: \.id) { overrideModel in
                    NavigationLink {
                        ProgramDayOverrideEditorView(overrideModel: overrideModel)
                            .appBackground()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(overrideModel.exercise?.name ?? "Unassigned Exercise")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text(overrideSubtitle(overrideModel))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deleteOverrides)
                .onMove(perform: moveOverrides)

                Button {
                    if let created = programService.addOverride(to: programDay) {
                        openedOverride = created
                    }
                } label: {
                    Label("Add Override", systemImage: "plus")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    saveProgramDay()
                }
            }
        }
        .navigationDestination(item: $openedOverride) { overrideModel in
            ProgramDayOverrideEditorView(overrideModel: overrideModel)
                .appBackground()
        }
    }

    private func saveProgramDay() {
        let selectedRoutine = routines.first(where: { $0.id == selectedRoutineId })

        _ = programService.updateProgramDay(
            programDay,
            title: titleText,
            weekIndex: max(0, (parseInt(weekNumberText) ?? (programDay.weekIndex + 1)) - 1),
            dayIndex: selectedWeekday,
            blockIndex: programDay.blockIndex,
            order: programDay.order,
            routine: selectedRoutine
        )

        dismiss()
    }

    private func deleteOverrides(at offsets: IndexSet) {
        let current = sortedOverrides
        for index in offsets {
            guard current.indices.contains(index) else { continue }
            _ = programService.removeOverride(current[index])
        }
    }

    private func moveOverrides(from source: IndexSet, to destination: Int) {
        programService.moveOverrides(in: programDay, from: source, to: destination)
    }

    private func overrideSubtitle(_ overrideModel: ProgramDayExerciseOverride) -> String {
        let sets = overrideModel.setsTarget.map { "sets \($0)" } ?? "sets -"
        let repsTarget = overrideModel.repsTarget.map { "reps \($0)" }
        let repsRange: String
        if let low = overrideModel.repsLow, let high = overrideModel.repsHigh {
            repsRange = "\(low)-\(high)"
        } else {
            repsRange = repsTarget ?? "reps -"
        }
        return "\(sets) · \(repsRange)"
    }

    private func parseInt(_ text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

}
