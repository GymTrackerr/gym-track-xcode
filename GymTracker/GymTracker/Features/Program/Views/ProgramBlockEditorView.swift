import SwiftUI

struct ProgramBlockEditorView: View {
    @EnvironmentObject var programService: ProgramService
    @Bindable var block: ProgramBlock

    @State private var titleText: String
    @State private var notesText: String
    @State private var startWeekText: String
    @State private var endWeekText: String
    @State private var showingAddTemplateDay = false
    @State private var openedTemplateDay: ProgramBlockTemplateDay?

    init(block: ProgramBlock) {
        self.block = block
        _titleText = State(initialValue: block.title)
        _notesText = State(initialValue: block.notes)
        _startWeekText = State(initialValue: String(block.startWeekIndex))
        _endWeekText = State(initialValue: String(block.endWeekIndex))
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
                    TextField("Start Week Index", text: $startWeekText)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    TextField("End Week Index", text: $endWeekText)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Button("Save Block") {
                        _ = programService.updateBlock(
                            block,
                            title: titleText,
                            notes: notesText,
                            startWeekIndex: Int(startWeekText) ?? 0,
                            endWeekIndex: Int(endWeekText) ?? 0
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Section("Weekly Template") {
                if sortedTemplateDays.isEmpty {
                    ContentUnavailableView("No template days yet", systemImage: "calendar")
                        .frame(maxWidth: .infinity)
                }
                ForEach(sortedTemplateDays, id: \.id) { templateDay in
                    Button {
                        openedTemplateDay = templateDay
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(templateDay.title)
                                .font(.headline)
                            Text("Weekday \(templateDay.weekDayIndex + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                    Label("Add Template Day", systemImage: "plus")
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

private struct AddTemplateDaySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var programService: ProgramService

    @Bindable var block: ProgramBlock

    @State private var titleText: String = ""
    @State private var weekDayText: String = "0"
    @State private var notesText: String = ""
    @State private var selectedRoutineId: UUID?

    private var routines: [Routine] {
        programService.activeRoutines()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Template Day") {
                    TextField("Title", text: $titleText)
                    TextField("Weekday Index (0-6)", text: $weekDayText)
                        .keyboardType(.numberPad)
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
            .navigationTitle("Add Template Day")
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
                            weekDayIndex: Int(weekDayText) ?? 0,
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
    @State private var weekDayText: String
    @State private var notesText: String
    @State private var selectedRoutineId: UUID?

    init(templateDay: ProgramBlockTemplateDay) {
        self.templateDay = templateDay
        _titleText = State(initialValue: templateDay.title)
        _weekDayText = State(initialValue: String(templateDay.weekDayIndex))
        _notesText = State(initialValue: templateDay.notes)
        _selectedRoutineId = State(initialValue: templateDay.routine?.id)
    }

    private var routines: [Routine] {
        programService.activeRoutines()
    }

    var body: some View {
        Form {
            Section("Template Day") {
                TextField("Title", text: $titleText)
                TextField("Weekday Index (0-6)", text: $weekDayText)
                    .keyboardType(.numberPad)
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
                        weekDayIndex: Int(weekDayText) ?? 0,
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
