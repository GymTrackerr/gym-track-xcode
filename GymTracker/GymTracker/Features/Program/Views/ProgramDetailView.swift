import SwiftUI

struct ProgramDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var sessionService: SessionService
    @EnvironmentObject var programService: ProgramService

    @Bindable var program: Program

    @State private var openedSession: Session?
    @State private var openedProgramDay: ProgramDay?

    @State private var nameText: String
    @State private var notesText: String
    @State private var isActive: Bool
    @State private var hasStartDate: Bool
    @State private var startDate: Date

    @State private var showingAddDaySheet = false
    @State private var showingArchiveConfirm = false
    @State private var showingDeleteConfirm = false

    init(program: Program) {
        self.program = program
        _nameText = State(initialValue: program.name)
        _notesText = State(initialValue: program.notes)
        _isActive = State(initialValue: program.isActive)
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

    var body: some View {
        List {
            metadataSection
            programDaysSection
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationTitle(program.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingAddDaySheet = true
                } label: {
                    Label("Add Day", systemImage: "plus")
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
        .sheet(isPresented: $showingAddDaySheet) {
            AddProgramDaySheet(program: program)
                .presentationDetents([.medium, .large])
        }
        .navigationDestination(item: $openedProgramDay) { day in
            ProgramDayEditorView(programDay: day)
                .appBackground()
        }
        .navigationDestination(item: $openedSession) { session in
            SingleSessionView(session: session)
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
                TextField("Program Name", text: $nameText)
                    .textFieldStyle(.roundedBorder)

                TextField("Notes", text: $notesText, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)

                Toggle("Active", isOn: $isActive)

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
                        startDate: hasStartDate ? startDate : nil
                    )
                }
                .buttonStyle(.borderedProminent)
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
                        openedProgramDay = day
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(day.title)
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)

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

                        Button(role: .destructive) {
                            _ = programService.removeProgramDay(day)
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.bordered)
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
                programService.moveProgramDays(in: program, from: source, to: destination)
            }
            .onDelete { offsets in
                let current = sortedProgramDays
                for index in offsets {
                    guard current.indices.contains(index) else { continue }
                    _ = programService.removeProgramDay(current[index])
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
