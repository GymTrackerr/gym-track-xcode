import SwiftUI

struct ProgramDayEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var programService: ProgramService

    @Bindable var programDay: ProgramDay
    @State private var openedOverride: ProgramDayExerciseOverride?

    @State private var titleText: String
    @State private var weekIndexText: String
    @State private var dayIndexText: String
    @State private var blockIndexText: String
    @State private var orderText: String
    @State private var selectedRoutineId: UUID?

    init(programDay: ProgramDay) {
        self.programDay = programDay
        _titleText = State(initialValue: programDay.title)
        _weekIndexText = State(initialValue: String(programDay.weekIndex))
        _dayIndexText = State(initialValue: String(programDay.dayIndex))
        _blockIndexText = State(initialValue: programDay.blockIndex.map(String.init) ?? "")
        _orderText = State(initialValue: String(programDay.order))
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
            Section("Day Metadata") {
                TextField("Title", text: $titleText)
                TextField("Week Index", text: $weekIndexText)
                    .keyboardType(.numberPad)
                TextField("Day Index", text: $dayIndexText)
                    .keyboardType(.numberPad)
                TextField("Block Index", text: $blockIndexText)
                    .keyboardType(.numberPad)
                TextField("Order", text: $orderText)
                    .keyboardType(.numberPad)

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
        .navigationTitle("Program Day")
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
            weekIndex: parseInt(weekIndexText) ?? programDay.weekIndex,
            dayIndex: parseInt(dayIndexText) ?? programDay.dayIndex,
            blockIndex: parseOptionalInt(blockIndexText),
            order: parseInt(orderText) ?? programDay.order,
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

    private func parseOptionalInt(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
    }
}
