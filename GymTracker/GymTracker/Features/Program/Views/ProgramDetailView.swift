//
//  ProgramDetailView.swift
//  GymTracker
//
//  Created by Codex on 2026-04-19.
//

import SwiftUI

struct ProgramDetailView: View {
    @EnvironmentObject private var programService: ProgramService
    @EnvironmentObject private var sessionService: SessionService
    @EnvironmentObject private var progressionService: ProgressionService

    let program: Program

    @State private var showingEditProgram = false
    @State private var showingAddBlock = false
    @State private var blockForNewWorkout: ProgramBlock?
    @State private var openedSession: Session?

    private var resolvedState: ProgramResolvedState {
        programService.resolvedState(for: program, sessions: sessionService.sessions)
    }

    private var visibleBlocks: [ProgramBlock] {
        programService.visibleBlocks(for: program)
    }

    private var directWorkoutBlock: ProgramBlock? {
        programService.directWorkoutBlock(for: program)
    }

    private var directWorkouts: [ProgramWorkout] {
        programService.directWorkouts(for: program)
    }

    private var isDirectWorkoutMode: Bool {
        programService.isDirectWorkoutMode(program)
    }

    private var defaultProgressionName: String {
        progressionService.profile(id: program.defaultProgressionProfileId)?.name ??
        program.defaultProgressionProfileNameSnapshot ??
        "None"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryCard
                if isDirectWorkoutMode {
                    directWorkoutsSection
                } else {
                    blocksSection
                }
            }
            .screenContentPadding()
        }
        .navigationTitle(program.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openedSession) { session in
            SingleSessionView(session: session)
                .appBackground()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isDirectWorkoutMode {
                    Button {
                        blockForNewWorkout = directWorkoutBlock
                    } label: {
                        Label("Add Workout", systemImage: "plus")
                    }
                } else {
                    Button {
                        showingAddBlock = true
                    } label: {
                        Label("Add Block", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditProgram) {
            NavigationStack {
                ProgramEditorSheet(program: program)
            }
        }
        .sheet(isPresented: $showingAddBlock) {
            NavigationStack {
                ProgramBlockEditorSheet(
                    program: program,
                    previousBlock: visibleBlocks.last
                )
            }
        }
        .sheet(item: $blockForNewWorkout) { block in
            NavigationStack {
                ProgramWorkoutEditorSheet(block: block)
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(program.name)
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(program.mode.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle(
                    "Active",
                    isOn: Binding(
                        get: { program.isActive },
                        set: { newValue in
                            if newValue {
                                programService.setActive(program)
                            } else if program.isActive {
                                programService.setActive(nil)
                            }
                        }
                    )
                )
                .labelsHidden()
            }

            if !program.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(program.notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            detailRow(title: "Structure", value: isDirectWorkoutMode ? "Continuous Workout Rotation" : "Blocks")
            detailRow(title: "Start Date", value: program.startDate.formatted(date: .abbreviated, time: .omitted))
            detailRow(title: "Schedule", value: resolvedState.scheduleLabel)
            detailRow(title: "Current Block", value: resolvedState.blockLabel)
            detailRow(title: "Progress", value: resolvedState.progressLabel)
            detailRow(title: "Progression", value: defaultProgressionName)
            detailRow(title: "Next Workout", value: resolvedState.nextWorkoutLabel)

            HStack(spacing: 10) {
                Button {
                    showingEditProgram = true
                } label: {
                    Label("Edit Program", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    openPrimaryWorkout()
                } label: {
                    Label(resolvedState.actionTitle, systemImage: resolvedState.activeSession == nil ? "play.fill" : "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canLaunchPrimaryWorkout)
            }

            if isDirectWorkoutMode {
                Button {
                    programService.convertToBlocksMode(program)
                } label: {
                    Label("Switch To Blocks", systemImage: "square.split.2x1")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var directWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Workouts")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("This program repeats the workout list forever. Add workouts directly and reorder them as needed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    blockForNewWorkout = directWorkoutBlock
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            if directWorkouts.isEmpty {
                emptyCard(
                    title: "No workouts yet",
                    subtitle: "Add a routine and the program will keep rotating through the workouts forever."
                )
            } else if let directWorkoutBlock {
                VStack(spacing: 12) {
                    ForEach(directWorkouts, id: \.id) { workout in
                        ProgramWorkoutRowCard(
                            program: program,
                            block: directWorkoutBlock,
                            workout: workout,
                            resolvedState: resolvedState,
                            showScheduleLabel: program.mode == .weekly,
                            onStart: { openSession(for: workout) },
                            onDelete: { programService.deleteWorkout(workout) },
                            onMoveUp: { programService.moveWorkout(workout, in: directWorkoutBlock, direction: .up) },
                            onMoveDown: { programService.moveWorkout(workout, in: directWorkoutBlock, direction: .down) },
                            canMoveUp: programService.canMoveWorkout(workout, in: directWorkoutBlock, direction: .up),
                            canMoveDown: programService.canMoveWorkout(workout, in: directWorkoutBlock, direction: .down)
                        )
                    }
                }
            }
        }
    }

    private var blocksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Blocks")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("Open a block to manage its workouts. Add the next block when you are ready to phase the program forward.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showingAddBlock = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            if visibleBlocks.isEmpty {
                emptyCard(
                    title: "No blocks yet",
                    subtitle: "Add a block if you want phased weeks or phased split passes instead of a single continuous workout rotation."
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(visibleBlocks, id: \.id) { block in
                        NavigationLink {
                            ProgramBlockDetailView(program: program, block: block)
                        } label: {
                            ProgramBlockSummaryCard(
                                block: block,
                                isCurrent: resolvedState.currentBlock?.id == block.id,
                                workoutCount: block.workouts.count,
                                durationSummary: durationSummary(for: block)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private func emptyCard(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var canLaunchPrimaryWorkout: Bool {
        if resolvedState.activeSession != nil {
            return true
        }
        return resolvedState.nextWorkout?.routine != nil
    }

    private func openPrimaryWorkout() {
        if let activeSession = resolvedState.activeSession {
            openedSession = activeSession
            return
        }

        guard let workout = resolvedState.nextWorkout else { return }
        openSession(for: workout)
    }

    private func openSession(for workout: ProgramWorkout) {
        if let activeSession = resolvedState.activeSession,
           activeSession.programWorkoutId == workout.id {
            openedSession = activeSession
            return
        }

        openedSession = sessionService.startProgramWorkout(program: program, workout: workout)
    }

    private func durationSummary(for block: ProgramBlock) -> String {
        if block.repeatsForever {
            return "Repeats forever"
        }

        let duration = max(block.durationCount, 1)
        switch program.mode {
        case .weekly:
            return "\(duration) week\(duration == 1 ? "" : "s")"
        case .continuous:
            return "\(duration) full split\(duration == 1 ? "" : "s")"
        }
    }
}

private struct ProgramBlockSummaryCard: View {
    let block: ProgramBlock
    let isCurrent: Bool
    let workoutCount: Int
    let durationSummary: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(block.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if isCurrent {
                        Text("CURRENT")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.14))
                            .clipShape(Capsule())
                    }
                }

                Text(durationSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(workoutCount) workout\(workoutCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct ProgramWorkoutRowCard: View {
    let program: Program
    let block: ProgramBlock
    let workout: ProgramWorkout
    let resolvedState: ProgramResolvedState
    let showScheduleLabel: Bool
    let onStart: () -> Void
    let onDelete: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let canMoveUp: Bool
    let canMoveDown: Bool

    private var activeSession: Session? {
        resolvedState.activeSession
    }

    private var isResumableWorkout: Bool {
        activeSession?.programWorkoutId == workout.id
    }

    private var isNextWorkout: Bool {
        activeSession == nil && resolvedState.nextWorkout?.id == workout.id
    }

    private var isLockedByAnotherActiveSession: Bool {
        activeSession != nil && !isResumableWorkout
    }

    private var labelText: String {
        if showScheduleLabel, let weekday = workout.resolvedWeekday {
            return weekday.title
        }
        return "Workout \(workout.order + 1)"
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(workout.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if isNextWorkout {
                        Text("NEXT")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.14))
                            .clipShape(Capsule())
                    }
                }

                Text(labelText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                Button {
                    onMoveUp()
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(!canMoveUp)

                Button {
                    onMoveDown()
                } label: {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.bordered)
                .disabled(!canMoveDown)

                Button {
                    onStart()
                } label: {
                    Text(isResumableWorkout ? "Resume" : "Start")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(minWidth: 64)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLockedByAnotherActiveSession || workout.routine == nil)

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(isResumableWorkout)
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct ProgramBlockDetailView: View {
    @EnvironmentObject private var programService: ProgramService
    @EnvironmentObject private var sessionService: SessionService
    @Environment(\.dismiss) private var dismiss

    let program: Program
    let block: ProgramBlock

    @State private var blockForNewWorkout: ProgramBlock?
    @State private var openedSession: Session?

    private var resolvedState: ProgramResolvedState {
        programService.resolvedState(for: program, sessions: sessionService.sessions)
    }

    private var sortedWorkouts: [ProgramWorkout] {
        block.workouts.sorted { lhs, rhs in
            if lhs.order == rhs.order {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.order < rhs.order
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(block.displayName)
                                .font(.title3)
                                .fontWeight(.semibold)

                            Text(durationSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if resolvedState.currentBlock?.id == block.id {
                            Text("CURRENT")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.14))
                                .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: 10) {
                        Button {
                            blockForNewWorkout = block
                        } label: {
                            Label("Add Workout", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            programService.deleteBlock(block)
                            dismiss()
                        } label: {
                            Label("Delete Block", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                if sortedWorkouts.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No workouts yet")
                            .font(.headline)
                        Text("Add workouts to this block. You can keep the same routines as the previous block or change them when the phase changes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    VStack(spacing: 12) {
                        ForEach(sortedWorkouts, id: \.id) { workout in
                            ProgramWorkoutRowCard(
                                program: program,
                                block: block,
                                workout: workout,
                                resolvedState: resolvedState,
                                showScheduleLabel: program.mode == .weekly,
                                onStart: { openSession(for: workout) },
                                onDelete: { programService.deleteWorkout(workout) },
                                onMoveUp: { programService.moveWorkout(workout, in: block, direction: .up) },
                                onMoveDown: { programService.moveWorkout(workout, in: block, direction: .down) },
                                canMoveUp: programService.canMoveWorkout(workout, in: block, direction: .up),
                                canMoveDown: programService.canMoveWorkout(workout, in: block, direction: .down)
                            )
                        }
                    }
                }
            }
            .screenContentPadding()
        }
        .navigationTitle(block.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openedSession) { session in
            SingleSessionView(session: session)
                .appBackground()
        }
        .sheet(item: $blockForNewWorkout) { block in
            NavigationStack {
                ProgramWorkoutEditorSheet(block: block)
            }
        }
    }

    private var durationSummary: String {
        if block.repeatsForever {
            return "Repeats forever"
        }

        let duration = max(block.durationCount, 1)
        switch program.mode {
        case .weekly:
            return "\(duration) week\(duration == 1 ? "" : "s")"
        case .continuous:
            return "\(duration) full split\(duration == 1 ? "" : "s")"
        }
    }

    private func openSession(for workout: ProgramWorkout) {
        if let activeSession = resolvedState.activeSession,
           activeSession.programWorkoutId == workout.id {
            openedSession = activeSession
            return
        }

        openedSession = sessionService.startProgramWorkout(program: program, workout: workout)
    }
}

struct ProgramEditorSheet: View {
    @EnvironmentObject private var programService: ProgramService
    @EnvironmentObject private var progressionService: ProgressionService
    @Environment(\.dismiss) private var dismiss

    let program: Program?

    @State private var name: String
    @State private var notes: String
    @State private var mode: ProgramMode
    @State private var startDate: Date
    @State private var trainDaysBeforeRest: Int
    @State private var restDays: Int
    @State private var isActive: Bool
    @State private var selectedProgressionProfileId: UUID?

    init(program: Program?) {
        self.program = program
        _name = State(initialValue: program?.name ?? "")
        _notes = State(initialValue: program?.notes ?? "")
        _mode = State(initialValue: program?.mode ?? .continuous)
        _startDate = State(initialValue: program?.startDate ?? Date())
        _trainDaysBeforeRest = State(initialValue: program?.trainDaysBeforeRest ?? 3)
        _restDays = State(initialValue: program?.restDays ?? 1)
        _isActive = State(initialValue: program?.isActive ?? false)
        _selectedProgressionProfileId = State(initialValue: program?.defaultProgressionProfileId)
    }

    var body: some View {
        Form {
            Section("Program") {
                TextField("Name", text: $name)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
                Picker("Schedule", selection: $mode) {
                    ForEach(ProgramMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                Toggle("Set Active", isOn: $isActive)
            }

            Section("Structure") {
                Text("New programs start as a continuous workout rotation. Add workouts directly after saving, or switch the program into blocks later when you want phases.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Progression") {
                Picker("Default Profile", selection: $selectedProgressionProfileId) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(progressionService.profiles, id: \.id) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }

                Text("Program-started sessions will use this profile for exercises that do not already have their own saved override.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if mode == .continuous {
                Section("Continuous Schedule") {
                    Stepper("Train Days Before Rest: \(trainDaysBeforeRest)", value: $trainDaysBeforeRest, in: 1...14)
                    Stepper("Rest Days: \(restDays)", value: $restDays, in: 0...7)
                }
            }
        }
        .navigationTitle(program == nil ? "New Program" : "Edit Program")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveProgram()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            progressionService.ensureBuiltInProfiles()
            progressionService.loadProfiles()
        }
    }

    private func saveProgram() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let program {
            let wasActive = program.isActive
            let selectedProfile = progressionService.profile(id: selectedProgressionProfileId)
            program.name = trimmedName
            program.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            program.mode = mode
            program.startDate = startDate
            program.trainDaysBeforeRest = max(trainDaysBeforeRest, 1)
            program.restDays = max(restDays, 0)
            program.defaultProgressionProfileId = selectedProfile?.id
            program.defaultProgressionProfileNameSnapshot = selectedProfile?.name
            programService.saveChanges(for: program)

            if isActive {
                programService.setActive(program)
            } else if wasActive {
                programService.setActive(nil)
            }
        } else if let program = programService.createProgram(
            name: trimmedName,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            mode: mode,
            startDate: startDate,
            trainDaysBeforeRest: trainDaysBeforeRest,
            restDays: restDays
        ) {
            let selectedProfile = progressionService.profile(id: selectedProgressionProfileId)
            program.defaultProgressionProfileId = selectedProfile?.id
            program.defaultProgressionProfileNameSnapshot = selectedProfile?.name
            programService.saveChanges(for: program)

            if isActive {
                programService.setActive(program)
            }
        }

        dismiss()
    }
}

private struct ProgramBlockEditorSheet: View {
    @EnvironmentObject private var programService: ProgramService
    @Environment(\.dismiss) private var dismiss

    let program: Program
    let previousBlock: ProgramBlock?

    @State private var name: String = ""
    @State private var durationCount: Int = 4
    @State private var repeatsForever = false
    @State private var copyPreviousBlock = false

    var body: some View {
        Form {
            Section("Block") {
                TextField("Name (optional)", text: $name)
                Toggle("Repeat Forever", isOn: $repeatsForever)

                if !repeatsForever {
                    Stepper(durationLabel, value: $durationCount, in: 1...24)
                }
            }

            if let previousBlock, !previousBlock.workouts.isEmpty {
                Section("Copy Previous Block") {
                    Toggle("Copy workouts from \(previousBlock.displayName)", isOn: $copyPreviousBlock)
                    Text("This copies the routines and workout order so you can tweak the next phase instead of rebuilding it from scratch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("New Block")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let block = programService.addBlock(
                        to: program,
                        name: trimmedName.isEmpty ? nil : trimmedName,
                        durationCount: repeatsForever ? 0 : durationCount
                    ) else {
                        return
                    }

                    if copyPreviousBlock, let previousBlock {
                        programService.copyWorkouts(from: previousBlock, to: block)
                    }

                    dismiss()
                }
            }
        }
    }

    private var durationLabel: String {
        switch program.mode {
        case .weekly:
            return "Weeks: \(durationCount)"
        case .continuous:
            return "Full Splits: \(durationCount)"
        }
    }
}

private struct ProgramWorkoutEditorSheet: View {
    @EnvironmentObject private var programService: ProgramService
    @EnvironmentObject private var routineService: RoutineService
    @Environment(\.dismiss) private var dismiss

    let block: ProgramBlock

    @State private var customName: String = ""
    @State private var selectedRoutineId: UUID?
    @State private var selectedWeekday: ProgramWeekday = .monday

    private var selectedRoutine: Routine? {
        routineService.routines.first(where: { $0.id == selectedRoutineId })
    }

    var body: some View {
        Form {
            Section("Workout") {
                if routineService.routines.isEmpty {
                    Text("Create a routine first, then come back and attach it to this workout slot.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Routine", selection: $selectedRoutineId) {
                        ForEach(routineService.routines, id: \.id) { routine in
                            Text(routine.name).tag(Optional(routine.id))
                        }
                    }
                }

                TextField("Custom Name (optional)", text: $customName)

                if block.program.mode == .weekly {
                    Picker("Day", selection: $selectedWeekday) {
                        ForEach(ProgramWeekday.allCases) { weekday in
                            Text(weekday.title).tag(weekday)
                        }
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
                Button("Save") {
                    let trimmedName = customName.trimmingCharacters(in: .whitespacesAndNewlines)
                    _ = programService.addWorkout(
                        to: block,
                        routine: selectedRoutine,
                        name: trimmedName.isEmpty ? nil : trimmedName,
                        weekdayIndex: block.program.mode == .weekly ? selectedWeekday.rawValue : nil
                    )
                    dismiss()
                }
                .disabled(selectedRoutine == nil)
            }
        }
        .onAppear {
            if selectedRoutineId == nil {
                selectedRoutineId = routineService.routines.first?.id
            }
        }
    }
}
