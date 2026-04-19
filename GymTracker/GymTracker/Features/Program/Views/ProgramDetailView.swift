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

    private var sortedBlocks: [ProgramBlock] {
        program.blocks.sorted { $0.order < $1.order }
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
                blocksSection
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
                Button {
                    showingAddBlock = true
                } label: {
                    Label("Add Block", systemImage: "plus")
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
                ProgramBlockEditorSheet(program: program)
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
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var blocksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Blocks")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    showingAddBlock = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            if sortedBlocks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No blocks yet")
                        .font(.headline)
                    Text("Blocks keep the program simple. Set how many weeks or full split passes each block should last, then add workouts underneath.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(spacing: 12) {
                    ForEach(sortedBlocks, id: \.id) { block in
                        blockCard(block)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func blockCard(_ block: ProgramBlock) -> some View {
        let workouts = block.workouts.sorted { lhs, rhs in
            if lhs.order == rhs.order {
                return lhs.displayName < rhs.displayName
            }
            return lhs.order < rhs.order
        }

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(block.displayName)
                            .font(.headline)

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

                    Text(durationSummary(for: block))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    blockForNewWorkout = block
                } label: {
                    Label("Workout", systemImage: "plus")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    programService.deleteBlock(block)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
            }

            if workouts.isEmpty {
                Text("No workouts in this block yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(workouts, id: \.id) { workout in
                        workoutRow(workout)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func workoutRow(_ workout: ProgramWorkout) -> some View {
        let activeSession = resolvedState.activeSession
        let isResumableWorkout = activeSession?.programWorkoutId == workout.id
        let isLockedByAnotherActiveSession = activeSession != nil && !isResumableWorkout

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(workoutLabel(for: workout))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                openSession(for: workout)
            } label: {
                Text(isResumableWorkout ? "Resume" : "Start")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .frame(minWidth: 64)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLockedByAnotherActiveSession || workout.routine == nil)

            Button(role: .destructive) {
                programService.deleteWorkout(workout)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(isResumableWorkout)
        }
        .padding(12)
        .background(Color.gray.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

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
        let duration = max(block.durationCount, 1)
        switch program.mode {
        case .weekly:
            return "\(duration) week\(duration == 1 ? "" : "s")"
        case .continuous:
            return "\(duration) full split\(duration == 1 ? "" : "s")"
        }
    }

    private func workoutLabel(for workout: ProgramWorkout) -> String {
        if program.mode == .weekly, let weekday = workout.resolvedWeekday {
            return weekday.title
        }
        return "Workout \(workout.order + 1)"
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
        _mode = State(initialValue: program?.mode ?? .weekly)
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
                Picker("Mode", selection: $mode) {
                    ForEach(ProgramMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                Toggle("Set Active", isOn: $isActive)
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

    @State private var name: String = ""
    @State private var durationCount: Int = 4

    var body: some View {
        Form {
            Section("Block") {
                TextField("Name (optional)", text: $name)
                Stepper(durationLabel, value: $durationCount, in: 1...24)
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
                    _ = programService.addBlock(
                        to: program,
                        name: trimmedName.isEmpty ? nil : trimmedName,
                        durationCount: durationCount
                    )
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
                    Text("Create a routine first, then come back and attach it to this block.")
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
