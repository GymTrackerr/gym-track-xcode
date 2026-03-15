import SwiftUI

struct ProgramsView: View {
    @EnvironmentObject var programService: ProgramService
    @EnvironmentObject var splitDayService: RoutineService
    @EnvironmentObject var sessionService: SessionService

    @State private var openedSession: Session?
    @State private var openedRoutine: Routine?
    @State private var openedProgram: Program?
    @State private var showingCreateSession = false
    @State private var showingCreateProgram = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                programsSection
                routinesSection
            }
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .navigationTitle("Programs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreateProgram = true
                } label: {
                    Label("Add Program", systemImage: "plus.circle")
                }
            }
        }
        .onAppear {
            programService.loadPrograms()
            splitDayService.loadSplitDays()
        }
        .sheet(isPresented: $showingCreateProgram) {
            CreateProgramSheetView()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingCreateSession) {
            CreateSessionSheetView(
                openedSession: $openedSession,
                isPresented: $showingCreateSession
            )
            .presentationDetents([.medium, .large])
        }
        .navigationDestination(item: $openedRoutine) { routine in
            SingleDayView(routine: routine)
                .appBackground()
        }
        .navigationDestination(item: $openedProgram) { program in
            ProgramDetailView(program: program)
                .appBackground()
        }
        .navigationDestination(item: $openedSession) { session in
            SingleSessionView(session: session)
                .appBackground()
        }
    }

    private var programsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Programs")
                .font(.headline)

            if programService.programs.isEmpty {
                ContentUnavailableView("No programs yet", systemImage: "calendar")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 8) {
                    ForEach(programService.programs, id: \.id) { program in
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                openedProgram = program
                            } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(program.name)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Spacer()
                                    if program.isCurrent {
                                        Text("Current")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.gray.opacity(0.14))
                                            .clipShape(Capsule())
                                    }
                                }

                                if let nextDayText = programService.nextScheduledDayText(for: program) {
                                    Text(nextDayText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if let block = programService.currentBlock(for: program) {
                                    Text("Block: \(block.title)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            }
                            .buttonStyle(.plain)

                            if !program.isCurrent {
                                Button("Set Current") {
                                    _ = programService.setCurrentProgram(program)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contextMenu {
                            Button {
                                _ = programService.setCurrentProgram(program)
                            } label: {
                                Label("Set Current", systemImage: "checkmark.circle")
                            }
                            .disabled(program.isCurrent)

                            Button(role: .destructive) {
                                _ = programService.archiveProgram(program)
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }

                            Button(role: .destructive) {
                                _ = programService.deleteProgramPermanentlyIfSafe(program)
                            } label: {
                                Label("Delete Permanently", systemImage: "trash")
                            }
                            .disabled(!programService.canDeleteProgramPermanently(program))
                        }
                    }
                }
            }
        }
    }

    private var routinesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Routines")
                .font(.headline)

            if splitDayService.routines.isEmpty {
                ContentUnavailableView("No routines yet", systemImage: "figure.walk.motion")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 8) {
                    ForEach(splitDayService.routines, id: \.id) { routine in
                        HStack(spacing: 12) {
                            Button {
                                openedRoutine = routine
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(routine.name)
                                        .font(.headline)
                                        .lineLimit(1)

                                    Text("\(routine.exerciseSplits.count) exercise\(routine.exerciseSplits.count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)

                            Button {
                                sessionService.selected_splitDay = routine
                                showingCreateSession = true
                            } label: {
                                Label("Start", systemImage: "play.fill")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(12)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }
}

private struct CreateProgramSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var programService: ProgramService

    @State private var nameText: String = ""
    @State private var notesText: String = ""
    @State private var isActive: Bool = false
    @State private var hasStartDate: Bool = false
    @State private var startDate: Date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Program") {
                    TextField("Name", text: $nameText)
                    TextField("Notes", text: $notesText, axis: .vertical)
                        .lineLimit(2...5)
                    Toggle("Active", isOn: $isActive)
                    Toggle("Has Start Date", isOn: $hasStartDate)
                    if hasStartDate {
                        DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("Create Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        _ = programService.addProgram(
                            name: nameText,
                            notes: notesText,
                            isActive: isActive,
                            startDate: hasStartDate ? startDate : nil
                        )
                        dismiss()
                    }
                    .disabled(nameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
