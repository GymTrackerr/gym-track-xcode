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
    @State private var showingArchivedPrograms = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                currentProgramWorkflowSection
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
            programService.loadArchivedPrograms()
            programService.loadProgressionSummary()
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

    private var currentProgramWorkflowSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Program")
                .font(.headline)

            if let current = programService.currentProgram() {
                let currentWeek = programService.effectiveCurrentWeek(for: current)
                let currentBlock = programService.currentBlock(for: current)
                let currentWorkout = programService.currentWorkout(for: current)
                let nextWorkout = programService.nextScheduledDay(for: current)
                let programProgress = programService.programProgress(for: current)
                let blockProgress = currentBlock.map { programService.blockProgress(for: current, block: $0) }
                let progressSummaryText = programService.progressSummaryText(for: current)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(current.name)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        Text("Current")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.14))
                            .clipShape(Capsule())
                    }

                    Text("Week \(currentWeek + 1)")
                        .font(.subheadline.weight(.semibold))

                    Text("Mode: \(programLengthModeLabel(for: current))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let block = currentBlock {
                        Text("Block: \(programService.displayBlockName(block))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Block: None")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let nextWorkout {
                        Text("Next Workout: \(programService.displayWorkoutName(for: nextWorkout))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Next Workout: Not available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let currentWorkout {
                        Text("Current Workout: \(programService.displayWorkoutName(for: currentWorkout))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let progressSummaryText {
                        Text(progressSummaryText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        progressChip(
                            title: "Program",
                            completed: programProgress.completed,
                            total: programProgress.total
                        )
                        if let blockProgress {
                            progressChip(
                                title: "Block",
                                completed: blockProgress.completed,
                                total: blockProgress.total
                            )
                        }
                    }

                    Button {
                        startNextWorkout(for: current)
                    } label: {
                        Label("Start Next Workout", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(nextWorkout == nil)

                    HStack(spacing: 8) {
                        Button("Skip") {
                            _ = programService.skipCurrentWorkout(for: current)
                        }
                        .buttonStyle(.bordered)

                        Button("Postpone") {
                            _ = programService.postponeCurrentWorkout(for: current)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                ContentUnavailableView("No current program", systemImage: "calendar.badge.exclamationmark")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
    }

    private var programsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Programs")
                .font(.headline)

            progressionSummaryCard

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

                                    Text(programLengthModeLabel(for: program))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    if let block = programService.currentBlock(for: program) {
                                        Text("Block: \(programService.displayBlockName(block))")
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

            archivedProgramsSection
        }
    }

    @ViewBuilder
    private var progressionSummaryCard: some View {
        if programService.progressionSummary.hasContent {
            HStack(spacing: 8) {
                compactSummaryMetric(
                    title: "Ready",
                    value: programService.progressionSummary.readyToIncrease
                )
                compactSummaryMetric(
                    title: "In Progress",
                    value: programService.progressionSummary.inProgress
                )
                compactSummaryMetric(
                    title: "Recent",
                    value: programService.progressionSummary.recentlyAdvanced
                )
            }
            .padding(10)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func compactSummaryMetric(title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func progressChip(title: String, completed: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(completed)/\(total)")
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var archivedProgramsSection: some View {
        DisclosureGroup(isExpanded: $showingArchivedPrograms) {
            if programService.archivedPrograms.isEmpty {
                Text("No archived programs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(programService.archivedPrograms, id: \.id) { program in
                        HStack(spacing: 12) {
                            Button {
                                openedProgram = program
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(program.name)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Text("Archived")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)

                            Button("Restore") {
                                _ = programService.restoreProgram(program)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(12)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(.top, 4)
            }
        } label: {
            HStack {
                Text("Archived Programs")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(programService.archivedPrograms.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func programLengthModeLabel(for program: Program) -> String {
        program.resolvedProgramLengthMode == .continuous ? "Continuous" : "Fixed Length"
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

    private func startNextWorkout(for program: Program) {
        guard let session = programService.startProgramSession(
            for: program,
            sessionService: sessionService
        ) else { return }
        openedSession = nil
        DispatchQueue.main.async {
            openedSession = session
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
