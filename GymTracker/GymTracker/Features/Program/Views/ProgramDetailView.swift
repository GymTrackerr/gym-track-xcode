import SwiftUI

struct ProgramDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var sessionService: SessionService
    @EnvironmentObject var programService: ProgramService

    @Bindable var program: Program

    @State private var openedSession: Session?
    @State private var openedProgramDay: ProgramDay?
    @State private var openedProgram: Program?

    @State private var nameText: String
    @State private var notesText: String
    @State private var isActive: Bool
    @State private var isCurrent: Bool
    @State private var hasStartDate: Bool
    @State private var startDate: Date

    @State private var showingAddDaySheet = false
    @State private var showingAddBlockSheet = false
    @State private var showingArchiveConfirm = false
    @State private var showingDeleteConfirm = false
    @State private var openedBlock: ProgramBlock?

    init(program: Program) {
        self.program = program
        _nameText = State(initialValue: program.name)
        _notesText = State(initialValue: program.notes)
        _isActive = State(initialValue: program.isActive)
        _isCurrent = State(initialValue: program.isCurrent)
        _hasStartDate = State(initialValue: program.startDate != nil)
        _startDate = State(initialValue: program.startDate ?? Date())
    }

    private var sortedProgramDays: [ProgramDay] {
        program.programDays.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            if lhs.weekIndex != rhs.weekIndex { return lhs.weekIndex < rhs.weekIndex }
            return lhs.dayIndex < rhs.dayIndex
        }
    }

    private var sortedBlocks: [ProgramBlock] {
        program.blocks.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.startWeekIndex < rhs.startWeekIndex
        }
    }

    var body: some View {
        List {
            metadataSection
            currentContextSection
            blocksSection
            programDaysSection
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationTitle(program.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !program.isBuiltIn {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingAddDaySheet = true
                    } label: {
                        Label("Add Day", systemImage: "plus")
                    }

                    Button {
                        showingAddBlockSheet = true
                    } label: {
                        Label("Add Block", systemImage: "rectangle.stack.badge.plus")
                    }

                    Menu {
                        Button(role: .destructive) {
                            showingArchiveConfirm = true
                        } label: {
                            Label("Archive Program", systemImage: "archivebox")
                        }

                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Label("Delete Permanently", systemImage: "trash")
                        }
                        .disabled(!programService.canDeleteProgramPermanently(program))
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddDaySheet) {
            AddProgramDaySheet(program: program)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingAddBlockSheet) {
            AddProgramBlockSheet(program: program)
                .presentationDetents([.medium, .large])
        }
        .navigationDestination(item: $openedProgramDay) { day in
            ProgramDayEditorView(programDay: day)
                .appBackground()
        }
        .navigationDestination(item: $openedBlock) { block in
            ProgramBlockEditorView(block: block)
                .appBackground()
        }
        .navigationDestination(item: $openedSession) { session in
            SingleSessionView(session: session)
                .appBackground()
        }
        .navigationDestination(item: $openedProgram) { nextProgram in
            ProgramDetailView(program: nextProgram)
                .appBackground()
        }
        .alert("Archive Program?", isPresented: $showingArchiveConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Archive", role: .destructive) {
                if programService.archiveProgram(program) {
                    dismiss()
                }
            }
        } message: {
            Text("This keeps historical sessions intact and hides the program from active lists.")
        }
        .alert("Delete Program Permanently?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if programService.deleteProgramPermanentlyIfSafe(program) {
                    dismiss()
                }
            }
        } message: {
            Text("Permanent delete is only available when no session history references this program.")
        }
    }

    private var metadataSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                if program.isBuiltIn {
                    Text(program.name)
                        .font(.headline)
                    Text("Built-in template. Duplicate to customize.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !program.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(program.notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Button("Duplicate to Edit") {
                        if let duplicated = programService.duplicateProgramForEditing(program) {
                            openedProgram = duplicated
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    TextField("Program Name", text: $nameText)
                        .textFieldStyle(.roundedBorder)

                    TextField("Notes", text: $notesText, axis: .vertical)
                        .lineLimit(2...5)
                        .textFieldStyle(.roundedBorder)

                    Toggle("Active", isOn: $isActive)
                    Toggle("Current Program", isOn: $isCurrent)

                    Toggle("Has Start Date", isOn: $hasStartDate)

                    if hasStartDate {
                        DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    }

                    Button("Save Program") {
                        _ = programService.updateProgram(
                            program,
                            name: nameText,
                            notes: notesText,
                            isActive: isActive,
                            startDate: hasStartDate ? startDate : nil,
                            isCurrent: isCurrent
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        .listRowBackground(Color.clear)
    }

    private var currentContextSection: some View {
        Section("Current Context") {
            VStack(alignment: .leading, spacing: 10) {
                let currentWeek = programService.effectiveCurrentWeek(for: program)
                Text("Current Week: \(currentWeek + 1)")
                    .font(.subheadline.weight(.semibold))
                if let block = programService.currentBlock(for: program) {
                    Text("Current Block: \(block.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Current Block: None")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let nextDay = programService.nextScheduledDay(for: program) {
                    Text("Next Day: \(nextDay.title) · Week \(nextDay.weekIndex + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Next Day: None")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !program.isBuiltIn {
                    HStack(spacing: 8) {
                        Button("Week -") {
                            let newWeek = max(0, currentWeek - 1)
                            _ = programService.setManualCurrentWeek(newWeek, for: program)
                        }
                        .buttonStyle(.bordered)
                        Button("Week +") {
                            _ = programService.setManualCurrentWeek(currentWeek + 1, for: program)
                        }
                        .buttonStyle(.bordered)
                        Button("Use Automatic") {
                            _ = programService.setManualCurrentWeek(nil, for: program)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button("Apply Blocks/Templates to Schedule") {
                        _ = programService.materializeTemplateSchedule(for: program)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        .listRowBackground(Color.clear)
    }

    private var blocksSection: some View {
        Section("Blocks") {
            if sortedBlocks.isEmpty {
                ContentUnavailableView("No blocks yet", systemImage: "rectangle.stack")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }

            ForEach(sortedBlocks, id: \.id) { block in
                Button {
                    if !program.isBuiltIn {
                        openedBlock = block
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(block.title)
                            .font(.headline)
                        Text("Weeks \(block.startWeekIndex + 1)-\(block.endWeekIndex + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(block.templateDays.count) template day\(block.templateDays.count == 1 ? "" : "s")")
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
                if !program.isBuiltIn {
                    let current = sortedBlocks
                    for index in offsets {
                        guard current.indices.contains(index) else { continue }
                        _ = programService.removeBlock(current[index])
                    }
                }
            }
        }
    }

    private var programDaysSection: some View {
        Section("Program Days") {
            if sortedProgramDays.isEmpty {
                ContentUnavailableView("No program days yet", systemImage: "calendar.badge.exclamationmark")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }

            ForEach(sortedProgramDays, id: \.id) { day in
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        if !program.isBuiltIn {
                            openedProgramDay = day
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(day.title)
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(day.isGeneratedFromTemplate ? "Generated" : "Manual")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.gray.opacity(0.14))
                                    .clipShape(Capsule())
                            }

                            Text("Week \(day.weekIndex + 1) · Day \(day.dayIndex + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(day.routine?.name ?? "No routine assigned")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 10) {
                        Button {
                            guard let session = sessionService.addSession(programDay: day) else { return }
                            openedSession = session
                        } label: {
                            Label("Start Session", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(day.routine == nil)

                        if !program.isBuiltIn {
                            Button(role: .destructive) {
                                _ = programService.removeProgramDay(day)
                            } label: {
                                Image(systemName: "trash")
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(12)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .onMove { source, destination in
                if !program.isBuiltIn {
                    programService.moveProgramDays(in: program, from: source, to: destination)
                }
            }
            .onDelete { offsets in
                if !program.isBuiltIn {
                    let current = sortedProgramDays
                    for index in offsets {
                        guard current.indices.contains(index) else { continue }
                        _ = programService.removeProgramDay(current[index])
                    }
                }
            }
        }
    }
}

private struct AddProgramDaySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var programService: ProgramService

    @Bindable var program: Program

    @State private var titleText: String = ""
    @State private var weekIndexText: String = "0"
    @State private var dayIndexText: String = "0"
    @State private var blockIndexText: String = ""
    @State private var selectedRoutineId: UUID?

    private var routines: [Routine] {
        programService.activeRoutines()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Day") {
                    TextField("Title", text: $titleText)
                    TextField("Week Index", text: $weekIndexText)
                        .keyboardType(.numberPad)
                    TextField("Day Index", text: $dayIndexText)
                        .keyboardType(.numberPad)
                    TextField("Block Index (optional)", text: $blockIndexText)
                        .keyboardType(.numberPad)
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
            .navigationTitle("Add Program Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addProgramDay()
                    }
                    .disabled(titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func addProgramDay() {
        let routine = routines.first(where: { $0.id == selectedRoutineId })

        _ = programService.addProgramDay(
            to: program,
            title: titleText,
            weekIndex: Int(weekIndexText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0,
            dayIndex: Int(dayIndexText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0,
            blockIndex: parseOptionalInt(blockIndexText),
            routine: routine
        )

        dismiss()
    }

    private func parseOptionalInt(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
    }
}

private struct AddProgramBlockSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var programService: ProgramService

    @Bindable var program: Program

    @State private var titleText: String = ""
    @State private var notesText: String = ""
    @State private var startWeekText: String = "0"
    @State private var endWeekText: String = "3"

    var body: some View {
        NavigationStack {
            Form {
                Section("Block") {
                    TextField("Title", text: $titleText)
                    TextField("Notes", text: $notesText, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Start Week Index", text: $startWeekText)
                        .keyboardType(.numberPad)
                    TextField("End Week Index", text: $endWeekText)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("Add Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        _ = programService.addBlock(
                            to: program,
                            title: titleText,
                            notes: notesText,
                            startWeekIndex: Int(startWeekText) ?? 0,
                            endWeekIndex: Int(endWeekText) ?? 0
                        )
                        dismiss()
                    }
                    .disabled(titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
