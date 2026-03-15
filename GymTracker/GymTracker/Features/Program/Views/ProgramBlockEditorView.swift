import SwiftUI

struct ProgramBlockEditorView: View {
    @EnvironmentObject var programService: ProgramService
    @Bindable var block: ProgramBlock

    @State private var titleText: String
    @State private var notesText: String
    @State private var startWeekText: String
    @State private var endWeekText: String
    @State private var scheduleMode: ProgramScheduleMode
    @State private var rotationOnDays: Int
    @State private var rotationOffDays: Int
    @State private var showingAddTemplateDay = false
    @State private var openedTemplateDay: ProgramBlockTemplateDay?

    init(block: ProgramBlock) {
        self.block = block
        _titleText = State(initialValue: block.title)
        _notesText = State(initialValue: block.notes)
        _startWeekText = State(initialValue: String(block.startWeekIndex + 1))
        _endWeekText = State(initialValue: String(block.endWeekIndex + 1))
        _scheduleMode = State(initialValue: block.resolvedScheduleMode)
        _rotationOnDays = State(initialValue: block.rotationOnDays ?? 3)
        _rotationOffDays = State(initialValue: block.rotationOffDays ?? 1)
    }

    private var sortedTemplateDays: [ProgramBlockTemplateDay] {
        block.templateDays.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.weekDayIndex < rhs.weekDayIndex
        }
    }

    var body: some View {
        List {
            Section("Block") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Title", text: $titleText)
                        .textFieldStyle(.roundedBorder)
                    TextField("Notes", text: $notesText, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                    TextField("Start Week", text: $startWeekText)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    TextField("End Week", text: $endWeekText)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Picker("Schedule Type", selection: $scheduleMode) {
                        Text("Calendar").tag(ProgramScheduleMode.calendar)
                        Text("Rotation").tag(ProgramScheduleMode.rotation)
                    }
                    .pickerStyle(.segmented)
                    if scheduleMode == .rotation {
                        Stepper("On Days: \(rotationOnDays)", value: $rotationOnDays, in: 1...7)
                        Stepper("Off Days: \(rotationOffDays)", value: $rotationOffDays, in: 0...6)
                    }
                    Button("Save Block") {
                        _ = programService.updateBlock(
                            block,
                            title: titleText,
                            notes: notesText,
                            startWeekIndex: max(0, (Int(startWeekText) ?? 1) - 1),
                            endWeekIndex: max(0, (Int(endWeekText) ?? 1) - 1),
                            scheduleMode: scheduleMode,
                            rotationOnDays: scheduleMode == .rotation ? rotationOnDays : nil,
                            rotationOffDays: scheduleMode == .rotation ? rotationOffDays : nil
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Section(scheduleMode == .calendar ? "Weekly Workouts" : "Workout Rotation") {
                if sortedTemplateDays.isEmpty {
                    ContentUnavailableView("No workouts yet", systemImage: "calendar")
                        .frame(maxWidth: .infinity)
                }
                ForEach(sortedTemplateDays, id: \.id) { templateDay in
                    Button {
                        openedTemplateDay = templateDay
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(templateDay.title)
                                .font(.headline)
                            if scheduleMode == .calendar {
                                Text("Weekday: \(weekdayLabel(for: templateDay.weekDayIndex))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Rotation order: \(templateDay.order + 1)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(templateDay.routine?.name ?? "No routine assigned")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    let current = sortedTemplateDays
                    for index in offsets {
                        guard current.indices.contains(index) else { continue }
                        _ = programService.removeTemplateDay(current[index])
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationTitle(block.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddTemplateDay = true
                } label: {
                    Label("Add Workout", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddTemplateDay) {
            AddTemplateDaySheet(block: block)
                .presentationDetents([.medium, .large])
        }
        .navigationDestination(item: $openedTemplateDay) { templateDay in
            ProgramBlockTemplateDayEditorView(templateDay: templateDay)
                .appBackground()
        }
    }
}

private func weekdayLabel(for dayIndex: Int) -> String {
    let labels = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    guard labels.indices.contains(dayIndex) else { return "Day \(dayIndex + 1)" }
    return labels[dayIndex]
}

private struct AddTemplateDaySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var programService: ProgramService

    @Bindable var block: ProgramBlock

    @State private var titleText: String = ""
    @State private var selectedWeekday: Int = 1
    @State private var notesText: String = ""
    @State private var selectedRoutineId: UUID?

    private var routines: [Routine] {
        programService.activeRoutines()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    TextField("Title", text: $titleText)
                    if block.resolvedScheduleMode == .calendar {
                        Picker("Weekday", selection: $selectedWeekday) {
                            Text("Sunday").tag(0)
                            Text("Monday").tag(1)
                            Text("Tuesday").tag(2)
                            Text("Wednesday").tag(3)
                            Text("Thursday").tag(4)
                            Text("Friday").tag(5)
                            Text("Saturday").tag(6)
                        }
                    } else {
                        Text("Rotation order is managed by list order.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    TextField("Notes", text: $notesText, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section("Routine") {
                    Picker("Assign Routine", selection: $selectedRoutineId) {
                        Text("None").tag(UUID?.none)
                        ForEach(routines, id: \.id) { routine in
                            Text(routine.name).tag(Optional(routine.id))
                        }
                    }
                }
            }
            .navigationTitle("Add Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let routine = routines.first(where: { $0.id == selectedRoutineId })
                        _ = programService.addTemplateDay(
                            to: block,
                            title: titleText,
                            weekDayIndex: block.resolvedScheduleMode == .calendar ? selectedWeekday : 0,
                            routine: routine,
                            notes: notesText
                        )
                        dismiss()
                    }
                    .disabled(titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct ProgramBlockTemplateDayEditorView: View {
    @EnvironmentObject var programService: ProgramService
    @Bindable var templateDay: ProgramBlockTemplateDay

    @State private var titleText: String
    @State private var selectedWeekday: Int
    @State private var notesText: String
    @State private var selectedRoutineId: UUID?

    init(templateDay: ProgramBlockTemplateDay) {
        self.templateDay = templateDay
        _titleText = State(initialValue: templateDay.title)
        _selectedWeekday = State(initialValue: templateDay.weekDayIndex)
        _notesText = State(initialValue: templateDay.notes)
        _selectedRoutineId = State(initialValue: templateDay.routine?.id)
    }

    private var routines: [Routine] {
        programService.activeRoutines()
    }

    var body: some View {
        Form {
            Section("Workout") {
                TextField("Title", text: $titleText)
                if templateDay.block?.resolvedScheduleMode == .calendar {
                    Picker("Weekday", selection: $selectedWeekday) {
                        Text("Sunday").tag(0)
                        Text("Monday").tag(1)
                        Text("Tuesday").tag(2)
                        Text("Wednesday").tag(3)
                        Text("Thursday").tag(4)
                        Text("Friday").tag(5)
                        Text("Saturday").tag(6)
                    }
                } else {
                    Text("Rotation order is managed by list order.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TextField("Notes", text: $notesText, axis: .vertical)
                    .lineLimit(2...4)
            }
            Section("Routine") {
                Picker("Assign Routine", selection: $selectedRoutineId) {
                    Text("None").tag(UUID?.none)
                    ForEach(routines, id: \.id) { routine in
                        Text(routine.name).tag(Optional(routine.id))
                    }
                }
            }
            Section {
                Button("Save Template Day") {
                    let routine = routines.first(where: { $0.id == selectedRoutineId })
                    _ = programService.updateTemplateDay(
                        templateDay,
                        title: titleText,
                        weekDayIndex: templateDay.block?.resolvedScheduleMode == .calendar ? selectedWeekday : templateDay.weekDayIndex,
                        routine: routine,
                        notes: notesText
                    )
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle(templateDay.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
