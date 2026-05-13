//
//  ProgramDetailView.swift
//  GymTracker
//
//  Created by Codex on 2026-04-19.
//

import SwiftUI

private func programmeNoneValue() -> String {
    String(localized: LocalizedStringResource(
        "programmes.value.none",
        defaultValue: "None",
        table: "Programmes"
    ))
}

private func programmeWorkoutFallbackName(order: Int) -> String {
    let workoutNumber = order + 1
    return String(localized: LocalizedStringResource(
        "programmes.workout.defaultName",
        defaultValue: "Workout \(workoutNumber)",
        table: "Programmes"
    ))
}

private func programmeDurationSummary(mode: ProgramMode, durationCount: Int, repeatsForever: Bool) -> String {
    if repeatsForever {
        return String(localized: LocalizedStringResource(
            "programmes.duration.repeatsForever",
            defaultValue: "Repeats forever",
            table: "Programmes"
        ))
    }

    let duration = max(durationCount, 1)
    switch mode {
    case .weekly:
        return String(localized: LocalizedStringResource(
            "programmes.duration.weeks",
            defaultValue: "\(duration) weeks",
            table: "Programmes"
        ))
    case .continuous:
        return String(localized: LocalizedStringResource(
            "programmes.duration.fullSplits",
            defaultValue: "\(duration) full splits",
            table: "Programmes"
        ))
    }
}

private func programmeWorkoutCount(_ count: Int) -> String {
    String(localized: LocalizedStringResource(
        "programmes.workout.count",
        defaultValue: "\(count) workouts",
        table: "Programmes"
    ))
}

private func programmeBlockSummary(workoutCount: Int, durationText: String) -> String {
    let workoutCountText = programmeWorkoutCount(workoutCount)
    return String(localized: LocalizedStringResource(
        "programmes.block.summary",
        defaultValue: "\(workoutCountText) • \(durationText)",
        table: "Programmes"
    ))
}

struct ProgramDetailView: View {
    @EnvironmentObject private var programService: ProgramService
    @EnvironmentObject private var sessionService: SessionService
    @EnvironmentObject private var progressionService: ProgressionService
    @Environment(\.dismiss) private var dismiss

    let program: Program

    @State private var showingManageProgram = false
    @State private var showingAddBlock = false
    @State private var blockForNewWorkout: ProgramBlock?
    @State private var openedSession: Session?

    init(program: Program) {
        self.program = program
    }

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
        programmeNoneValue()
    }

    private var previousSessions: [Session] {
        programService.completedSessions(for: program, sessions: sessionService.sessions)
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
                previousSessionsSection
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
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingManageProgram = true
                } label: {
                    Label {
                        Text(LocalizedStringResource("programmes.action.edit", defaultValue: "Edit", table: "Programmes"))
                    } icon: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }

                if isDirectWorkoutMode {
                    Button {
                        blockForNewWorkout = directWorkoutBlock
                    } label: {
                        Label {
                            Text(LocalizedStringResource("programmes.action.addWorkout", defaultValue: "Add Workout", table: "Programmes"))
                        } icon: {
                            Image(systemName: "plus")
                        }
                    }
                } else {
                    Button {
                        showingAddBlock = true
                    } label: {
                        Label {
                            Text(LocalizedStringResource("programmes.action.addBlock", defaultValue: "Add Block", table: "Programmes"))
                        } icon: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingManageProgram) {
            NavigationStack {
                ProgramManagementSheet(program: program) {
                    dismiss()
                }
            }
            .editorSheetPresentation()
        }
        .sheet(isPresented: $showingAddBlock) {
            NavigationStack {
                ProgramBlockEditorSheet(
                    program: program,
                    previousBlock: visibleBlocks.last
                )
            }
            .editorSheetPresentation()
        }
        .sheet(item: $blockForNewWorkout) { block in
            NavigationStack {
                ProgramWorkoutEditorSheet(block: block)
            }
            .editorSheetPresentation()
        }
    }

    private var summaryCard: some View {
        CardRowContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: program.name)
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text(program.mode.titleResource)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if program.isActive {
                            Text(LocalizedStringResource("programmes.status.active", defaultValue: "ACTIVE", table: "Programmes"))
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.14))
                                .clipShape(Capsule())
                        }
                    }

                    Spacer()
                }

            if !program.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(verbatim: program.notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            detailRow(
                title: LocalizedStringResource("programmes.detail.structure", defaultValue: "Structure", table: "Programmes"),
                value: isDirectWorkoutMode ? String(localized: LocalizedStringResource("programmes.structure.continuousWorkoutRotation", defaultValue: "Continuous Workout Rotation", table: "Programmes")) : String(localized: LocalizedStringResource("programmes.structure.blocks", defaultValue: "Blocks", table: "Programmes"))
            )
            detailRow(title: LocalizedStringResource("programmes.detail.startDate", defaultValue: "Start Date", table: "Programmes"), value: program.startDate.formatted(date: .abbreviated, time: .omitted))
            detailRow(title: LocalizedStringResource("programmes.detail.schedule", defaultValue: "Schedule", table: "Programmes"), value: resolvedState.scheduleLabel)
            detailRow(title: LocalizedStringResource("programmes.detail.currentBlock", defaultValue: "Current Block", table: "Programmes"), value: resolvedState.blockLabel)
            detailRow(title: LocalizedStringResource("programmes.detail.progress", defaultValue: "Progress", table: "Programmes"), value: resolvedState.progressLabel)
            detailRow(title: LocalizedStringResource("programmes.detail.progression", defaultValue: "Progression", table: "Programmes"), value: defaultProgressionName)
            detailRow(title: LocalizedStringResource("programmes.detail.nextWorkout", defaultValue: "Next Workout", table: "Programmes"), value: resolvedState.nextWorkoutLabel)

            Button {
                openPrimaryWorkout()
            } label: {
                Label {
                    Text(verbatim: resolvedState.actionTitle)
                } icon: {
                    Image(systemName: resolvedState.activeSession == nil ? "play.fill" : "arrow.clockwise")
                }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canLaunchPrimaryWorkout)

            if resolvedState.activeSession == nil {
                Button {
                    programService.skipNextWorkout(for: program, sessions: sessionService.sessions)
                } label: {
                    Label {
                        Text(LocalizedStringResource("programmes.action.skipWorkout", defaultValue: "Skip Workout", table: "Programmes"))
                    } icon: {
                        Image(systemName: "forward.fill")
                    }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!resolvedState.canSkipNextWorkout)
            }
            }
        }
    }

    private var previousSessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderView(
                resourceTitle: LocalizedStringResource("programmes.detail.previousSessions", defaultValue: "Previous Sessions", table: "Programmes"),
                resourceSubtitle: LocalizedStringResource("programmes.detail.previousSessions.subtitle", defaultValue: "Quickly jump back into your recent programme workouts.", table: "Programmes")
            )

            if previousSessions.isEmpty {
                emptyCard(
                    title: LocalizedStringResource("programmes.detail.previousSessions.empty.title", defaultValue: "No programme sessions yet", table: "Programmes"),
                    subtitle: LocalizedStringResource("programmes.detail.previousSessions.empty.subtitle", defaultValue: "Once you finish workouts from this programme, they will show up here.", table: "Programmes")
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(previousSessions.prefix(8)), id: \.id) { session in
                        Button {
                            openedSession = session
                        } label: {
                            SingleSessionLabelView(session: session)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(CardRowBackground())
                                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var directWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeaderView(
                    resourceTitle: LocalizedStringResource("programmes.detail.workouts", defaultValue: "Workouts", table: "Programmes"),
                    resourceSubtitle: LocalizedStringResource("programmes.detail.workouts.subtitle", defaultValue: "This programme repeats the workout list forever. Use Edit to reorder workouts or switch the structure later.", table: "Programmes")
                )

                Spacer()

                Button {
                    blockForNewWorkout = directWorkoutBlock
                } label: {
                    Label {
                        Text(LocalizedStringResource("programmes.action.add", defaultValue: "Add", table: "Programmes"))
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
                .buttonStyle(.bordered)
            }

            if directWorkouts.isEmpty {
                emptyCard(
                    title: LocalizedStringResource("programmes.detail.workouts.empty.title", defaultValue: "No workouts yet", table: "Programmes"),
                    subtitle: LocalizedStringResource("programmes.detail.workouts.empty.subtitle", defaultValue: "Add a routine and the programme will keep rotating through the workouts forever.", table: "Programmes")
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(directWorkouts, id: \.id) { workout in
                        ProgramWorkoutRowCard(
                            workout: workout,
                            resolvedState: resolvedState,
                            showScheduleLabel: program.mode == .weekly,
                            onStart: { openSession(for: workout) }
                        )
                    }
                }
            }
        }
    }

    private var blocksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeaderView(
                    resourceTitle: LocalizedStringResource("programmes.detail.blocks", defaultValue: "Blocks", table: "Programmes"),
                    resourceSubtitle: LocalizedStringResource("programmes.detail.blocks.subtitle", defaultValue: "Open a block to manage its workouts. Add the next block when you are ready to phase the programme forward.", table: "Programmes")
                )

                Spacer()

                Button {
                    showingAddBlock = true
                } label: {
                    Label {
                        Text(LocalizedStringResource("programmes.action.add", defaultValue: "Add", table: "Programmes"))
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
                .buttonStyle(.bordered)
            }

            if visibleBlocks.isEmpty {
                emptyCard(
                    title: LocalizedStringResource("programmes.detail.blocks.empty.title", defaultValue: "No blocks yet", table: "Programmes"),
                    subtitle: LocalizedStringResource("programmes.detail.blocks.empty.subtitle", defaultValue: "Add a block if you want phased weeks or phased split passes instead of a single continuous workout rotation.", table: "Programmes")
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
    private func detailRow(title: LocalizedStringResource, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: value)
                .font(.caption)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private func emptyCard(title: LocalizedStringResource, subtitle: LocalizedStringResource) -> some View {
        CardRowContainer {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var canLaunchPrimaryWorkout: Bool {
        resolvedState.canStartNextWorkout
    }

    private func openPrimaryWorkout() {
        if !program.isActive {
            programService.setActive(program)
        }

        if let activeSession = resolvedState.activeSession {
            openedSession = activeSession
            return
        }

        guard let workout = resolvedState.nextWorkout else { return }
        openSession(for: workout)
    }

    private func openSession(for workout: ProgramWorkout) {
        if !program.isActive {
            programService.setActive(program)
        }

        if let activeSession = resolvedState.activeSession,
           activeSession.programWorkoutId == workout.id {
            openedSession = activeSession
            return
        }

        openedSession = sessionService.startProgramWorkout(program: program, workout: workout)
    }

    private func durationSummary(for block: ProgramBlock) -> String {
        programmeDurationSummary(
            mode: program.mode,
            durationCount: block.durationCount,
            repeatsForever: block.repeatsForever
        )
    }

}

private struct ProgramBlockSummaryCard: View {
    let block: ProgramBlock
    let isCurrent: Bool
    let workoutCount: Int
    let durationSummary: String

    var body: some View {
        CardRowContainer {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(verbatim: block.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if isCurrent {
                            Text(LocalizedStringResource("programmes.status.current", defaultValue: "CURRENT", table: "Programmes"))
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

                    Text(verbatim: programmeWorkoutCount(workoutCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ProgramWorkoutRowCard: View {
    @EnvironmentObject private var programService: ProgramService
    let workout: ProgramWorkout
    let resolvedState: ProgramResolvedState
    let showScheduleLabel: Bool
    let onStart: () -> Void

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
        return programmeWorkoutFallbackName(order: workout.order)
    }

    var body: some View {
        CardRowContainer {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(verbatim: workout.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        if isNextWorkout {
                            Text(LocalizedStringResource("programmes.status.next", defaultValue: "NEXT", table: "Programmes"))
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.14))
                                .clipShape(Capsule())
                        }
                    }

                    Text(verbatim: labelText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onStart()
                } label: {
                    Text(isResumableWorkout
                         ? LocalizedStringResource("programmes.action.resume", defaultValue: "Resume", table: "Programmes")
                         : LocalizedStringResource("programmes.action.start", defaultValue: "Start", table: "Programmes"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(minWidth: 64)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLockedByAnotherActiveSession || !programService.isWorkoutStartable(workout))
            }
        }
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
    @State private var showingManageWorkouts = false

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
                CardRowContainer {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(verbatim: block.displayName)
                                    .font(.title3)
                                    .fontWeight(.semibold)

                                Text(durationSummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if resolvedState.currentBlock?.id == block.id {
                                Text(LocalizedStringResource("programmes.status.current", defaultValue: "CURRENT", table: "Programmes"))
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
                                Label {
                                    Text(LocalizedStringResource("programmes.action.addWorkout", defaultValue: "Add Workout", table: "Programmes"))
                                } icon: {
                                    Image(systemName: "plus")
                                }
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                showingManageWorkouts = true
                            } label: {
                                Label {
                                    Text(LocalizedStringResource("programmes.action.edit", defaultValue: "Edit", table: "Programmes"))
                                } icon: {
                                    Image(systemName: "slider.horizontal.3")
                                }
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                if sortedWorkouts.isEmpty {
                    CardRowContainer {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(LocalizedStringResource("programmes.detail.workouts.empty.title", defaultValue: "No workouts yet", table: "Programmes"))
                                .font(.headline)
                            Text(LocalizedStringResource("programmes.blockDetail.empty.subtitle", defaultValue: "Add workouts to this block. You can keep the same routines as the previous block or change them when the phase changes.", table: "Programmes"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        ForEach(sortedWorkouts, id: \.id) { workout in
                            ProgramWorkoutRowCard(
                                workout: workout,
                                resolvedState: resolvedState,
                                showScheduleLabel: program.mode == .weekly,
                                onStart: { openSession(for: workout) }
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
            .editorSheetPresentation()
        }
        .sheet(isPresented: $showingManageWorkouts) {
            NavigationStack {
                ProgramBlockManagementSheet(program: program, block: block) {
                    dismiss()
                }
            }
            .editorSheetPresentation()
        }
    }

    private var durationSummary: String {
        programmeDurationSummary(
            mode: program.mode,
            durationCount: block.durationCount,
            repeatsForever: block.repeatsForever
        )
    }

    private func openSession(for workout: ProgramWorkout) {
        if !program.isActive {
            programService.setActive(program)
        }

        if let activeSession = resolvedState.activeSession,
           activeSession.programWorkoutId == workout.id {
            openedSession = activeSession
            return
        }

        openedSession = sessionService.startProgramWorkout(program: program, workout: workout)
    }
}

private struct ProgramManagementSheet: View {
    @EnvironmentObject private var programService: ProgramService
    @Environment(\.dismiss) private var dismiss

    @Bindable var program: Program
    let onDelete: () -> Void

    @State private var editMode: EditMode = .active
    @State private var showingProgramEditor = false
    @State private var blockForNewWorkout: ProgramBlock?
    @State private var showingDeleteConfirmation = false

    private var directWorkoutBlock: ProgramBlock? {
        programService.directWorkoutBlock(for: program)
    }

    private var visibleBlocks: [ProgramBlock] {
        programService.visibleBlocks(for: program)
    }

    private var managedBlock: ProgramBlock? {
        if programService.isDirectWorkoutMode(program) {
            return directWorkoutBlock
        }
        if visibleBlocks.count == 1 {
            return visibleBlocks.first
        }
        return nil
    }

    private var managedWorkouts: [ProgramWorkout] {
        guard let managedBlock else { return [] }
        return managedBlock.workouts.sorted { lhs, rhs in
            if lhs.order == rhs.order {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.order < rhs.order
        }
    }

    private var deletesAsArchive: Bool {
        programService.willArchiveOnDelete(program)
    }

    private var deleteDialogTitle: String {
        String(localized: deletesAsArchive
               ? LocalizedStringResource("programmes.dialog.archive.title", defaultValue: "Archive Programme?", table: "Programmes")
               : LocalizedStringResource("programmes.dialog.delete.title", defaultValue: "Delete Programme?", table: "Programmes"))
    }

    private var deleteActionTitle: String {
        String(localized: deletesAsArchive
               ? LocalizedStringResource("programmes.action.archiveProgramme", defaultValue: "Archive Programme", table: "Programmes")
               : LocalizedStringResource("programmes.action.deleteProgramme", defaultValue: "Delete Programme", table: "Programmes"))
    }

    private var deleteMessageResource: LocalizedStringResource {
        deletesAsArchive
        ? LocalizedStringResource("programmes.dialog.archive.message", defaultValue: "This programme already has session history, so it will be archived instead of permanently deleted.", table: "Programmes")
        : LocalizedStringResource("programmes.dialog.delete.message", defaultValue: "This will permanently delete the programme because it has not been used yet.", table: "Programmes")
    }

    var body: some View {
        List {
            actionsSection

            if let managedBlock {
                workoutsSection(for: managedBlock)
            } else {
                blocksSection
            }
        }
        .cardListScreen()
        .environment(\.editMode, $editMode)
        .navigationTitle(String(localized: LocalizedStringResource("programmes.editor.editProgramme", defaultValue: "Edit Programme", table: "Programmes")))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Text(LocalizedStringResource("programmes.action.done", defaultValue: "Done", table: "Programmes"))
                }
            }

            if let managedBlock {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        blockForNewWorkout = managedBlock
                    } label: {
                        Label {
                            Text(LocalizedStringResource("programmes.action.addWorkout", defaultValue: "Add Workout", table: "Programmes"))
                        } icon: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingProgramEditor) {
            NavigationStack {
                ProgramEditorSheet(program: program)
            }
            .editorSheetPresentation()
        }
        .sheet(item: $blockForNewWorkout) { block in
            NavigationStack {
                ProgramWorkoutEditorSheet(block: block)
            }
            .editorSheetPresentation()
        }
        .confirmationDialog(deleteDialogTitle, isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button(deleteActionTitle, role: .destructive) {
                programService.delete(program)
                dismiss()
                DispatchQueue.main.async {
                    onDelete()
                }
            }
            Button(String(localized: LocalizedStringResource("programmes.action.cancel", defaultValue: "Cancel", table: "Programmes")), role: .cancel) {}
        } message: {
            Text(deleteMessageResource)
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                showingProgramEditor = true
            } label: {
                Label {
                    Text(LocalizedStringResource("programmes.action.editProgrammeDetails", defaultValue: "Edit Programme Details", table: "Programmes"))
                } icon: {
                    Image(systemName: "pencil")
                }
                    .cardListRowContentPadding()
            }
            .cardListRowStyle()

            if programService.isDirectWorkoutMode(program) {
                Button {
                    programService.convertToBlocksMode(program)
                } label: {
                    Label {
                        Text(LocalizedStringResource("programmes.action.switchToBlocks", defaultValue: "Switch To Blocks", table: "Programmes"))
                    } icon: {
                        Image(systemName: "square.split.2x1")
                    }
                        .cardListRowContentPadding()
                }
                .cardListRowStyle()
            } else if programService.canConvertToDirectWorkoutMode(program) {
                Button {
                    programService.convertToDirectWorkoutMode(program)
                } label: {
                    Label {
                        Text(LocalizedStringResource("programmes.action.useWorkoutRotation", defaultValue: "Use Workout Rotation", table: "Programmes"))
                    } icon: {
                        Image(systemName: "repeat")
                    }
                        .cardListRowContentPadding()
                }
                .cardListRowStyle()
            }

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label {
                    Text(verbatim: deleteActionTitle)
                } icon: {
                    Image(systemName: "trash")
                }
                    .cardListRowContentPadding()
            }
            .cardListRowStyle()
        } header: {
            Text(LocalizedStringResource("programmes.section.actions", defaultValue: "Actions", table: "Programmes"))
        }
    }

    private func workoutsSection(for block: ProgramBlock) -> some View {
        Section {
            if managedWorkouts.isEmpty {
                Text(LocalizedStringResource("programmes.management.workouts.empty", defaultValue: "Add workouts to get this programme moving.", table: "Programmes"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .cardListRowContentPadding()
                    .cardListRowStyle()
            } else {
                ForEach(managedWorkouts, id: \.id) { workout in
                    ProgramWorkoutManageRow(workout: workout, showScheduleLabel: program.mode == .weekly)
                        .cardListRowStyle()
                }
                .onMove { source, destination in
                    programService.moveWorkouts(in: block, from: source, to: destination)
                }
                .onDelete { offsets in
                    deleteWorkouts(at: offsets, from: block)
                }
            }
        } header: {
            if programService.isDirectWorkoutMode(program) {
                Text(LocalizedStringResource("programmes.section.workoutOrder", defaultValue: "Workout Order", table: "Programmes"))
            } else {
                Text(verbatim: block.displayName)
            }
        } footer: {
            Text(LocalizedStringResource("programmes.management.workoutOrder.footer", defaultValue: "Drag workouts to reorder them. Swipe to delete if you need to remove one.", table: "Programmes"))
        }
    }

    private var blocksSection: some View {
        Section {
            ForEach(visibleBlocks, id: \.id) { block in
                NavigationLink {
                    ProgramBlockManagementSheet(program: program, block: block)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: block.displayName)
                                .font(.body.weight(.semibold))
                            Text(blockSummary(for: block))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .cardListRowContentPadding()
                }
                .cardListRowStyle()
            }
        } header: {
            Text(LocalizedStringResource("programmes.detail.blocks", defaultValue: "Blocks", table: "Programmes"))
        } footer: {
            Text(LocalizedStringResource("programmes.management.blocks.footer", defaultValue: "Open a block to reorder its workouts with drag and drop.", table: "Programmes"))
        }
    }

    private func deleteWorkouts(at offsets: IndexSet, from block: ProgramBlock) {
        let workouts = managedWorkouts
        let items = offsets.compactMap { index in
            workouts.indices.contains(index) ? workouts[index] : nil
        }
        for workout in items {
            programService.deleteWorkout(workout)
        }
    }

    private func blockSummary(for block: ProgramBlock) -> String {
        let workoutCount = block.workouts.count
        let durationText: String
        durationText = programmeDurationSummary(
            mode: program.mode,
            durationCount: block.durationCount,
            repeatsForever: block.repeatsForever
        )

        return programmeBlockSummary(workoutCount: workoutCount, durationText: durationText)
    }
}

private struct ProgramBlockManagementSheet: View {
    @EnvironmentObject private var programService: ProgramService
    @Environment(\.dismiss) private var dismiss

    @Bindable var program: Program
    @Bindable var block: ProgramBlock
    let onDelete: (() -> Void)?

    @State private var editMode: EditMode = .active
    @State private var blockForNewWorkout: ProgramBlock?
    @State private var showingDeleteConfirmation = false

    init(program: Program, block: ProgramBlock, onDelete: (() -> Void)? = nil) {
        self.program = program
        self.block = block
        self.onDelete = onDelete
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
        List {
            Section {
                Text(verbatim: block.displayName)
                    .font(.body.weight(.semibold))
                    .cardListRowContentPadding()
                    .cardListRowStyle()
                Text(blockDurationSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .cardListRowContentPadding()
                    .cardListRowStyle()
            } header: {
                Text(LocalizedStringResource("programmes.section.block", defaultValue: "Block", table: "Programmes"))
            }

            Section {
                if sortedWorkouts.isEmpty {
                    Text(LocalizedStringResource("programmes.blockManagement.empty", defaultValue: "Add workouts to start this block.", table: "Programmes"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .cardListRowContentPadding()
                        .cardListRowStyle()
                } else {
                    ForEach(sortedWorkouts, id: \.id) { workout in
                        ProgramWorkoutManageRow(workout: workout, showScheduleLabel: program.mode == .weekly)
                            .cardListRowStyle()
                    }
                    .onMove { source, destination in
                        programService.moveWorkouts(in: block, from: source, to: destination)
                    }
                    .onDelete { offsets in
                        deleteWorkouts(at: offsets)
                    }
                }
            } header: {
                Text(LocalizedStringResource("programmes.section.workoutOrder", defaultValue: "Workout Order", table: "Programmes"))
            } footer: {
                Text(LocalizedStringResource("programmes.management.workoutOrder.footer", defaultValue: "Drag workouts to reorder them. Swipe to delete if you need to remove one.", table: "Programmes"))
            }

            Section {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label {
                        Text(LocalizedStringResource("programmes.action.deleteBlock", defaultValue: "Delete Block", table: "Programmes"))
                    } icon: {
                        Image(systemName: "trash")
                    }
                        .cardListRowContentPadding()
                }
                .cardListRowStyle()
            }
        }
        .cardListScreen()
        .environment(\.editMode, $editMode)
        .navigationTitle(String(localized: LocalizedStringResource("programmes.editor.editBlock", defaultValue: "Edit Block", table: "Programmes")))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Text(LocalizedStringResource("programmes.action.done", defaultValue: "Done", table: "Programmes"))
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    blockForNewWorkout = block
                } label: {
                    Label {
                        Text(LocalizedStringResource("programmes.action.addWorkout", defaultValue: "Add Workout", table: "Programmes"))
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(item: $blockForNewWorkout) { block in
            NavigationStack {
                ProgramWorkoutEditorSheet(block: block)
            }
            .editorSheetPresentation()
        }
        .confirmationDialog(String(localized: LocalizedStringResource("programmes.dialog.deleteBlock.title", defaultValue: "Delete Block?", table: "Programmes")), isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button(String(localized: LocalizedStringResource("programmes.action.deleteBlock", defaultValue: "Delete Block", table: "Programmes")), role: .destructive) {
                programService.deleteBlock(block)
                dismiss()
                DispatchQueue.main.async {
                    onDelete?()
                }
            }
            Button(String(localized: LocalizedStringResource("programmes.action.cancel", defaultValue: "Cancel", table: "Programmes")), role: .cancel) {}
        } message: {
            Text(LocalizedStringResource("programmes.dialog.deleteBlock.message", defaultValue: "This removes the block and all of its workout slots.", table: "Programmes"))
        }
    }

    private var blockDurationSummary: String {
        programmeDurationSummary(
            mode: program.mode,
            durationCount: block.durationCount,
            repeatsForever: block.repeatsForever
        )
    }

    private func deleteWorkouts(at offsets: IndexSet) {
        let items = offsets.compactMap { index in
            sortedWorkouts.indices.contains(index) ? sortedWorkouts[index] : nil
        }
        for workout in items {
            programService.deleteWorkout(workout)
        }
    }
}

private struct ProgramWorkoutManageRow: View {
    let workout: ProgramWorkout
    let showScheduleLabel: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: workout.displayName)
                .font(.body.weight(.semibold))

            if showScheduleLabel, let weekday = workout.resolvedWeekday {
                Text(verbatim: weekday.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(verbatim: programmeWorkoutFallbackName(order: workout.order))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardListRowContentPadding()
    }
}

struct ProgramEditorSheet: View {
    @EnvironmentObject private var programService: ProgramService
    @EnvironmentObject private var progressionService: ProgressionService
    @Environment(\.dismiss) private var dismiss

    let program: Program?
    let onSave: ((Program) -> Void)?

    @State private var name: String
    @State private var notes: String
    @State private var mode: ProgramMode
    @State private var startDate: Date
    @State private var trainDaysBeforeRest: Int
    @State private var restDays: Int
    @State private var isActive: Bool
    @State private var selectedProgressionProfileId: UUID?

    init(program: Program?, onSave: ((Program) -> Void)? = nil) {
        self.program = program
        self.onSave = onSave
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeaderView(resourceTitle: LocalizedStringResource("programmes.section.programme", defaultValue: "Programme", table: "Programmes"))
                    ConnectedCardSection {
                        ConnectedCardRow {
                            LabeledContent {
                                TextField(
                                    text: $name,
                                    prompt: Text(LocalizedStringResource("programmes.placeholder.required", defaultValue: "Required", table: "Programmes"))
                                ) {
                                    Text(LocalizedStringResource("programmes.field.name", defaultValue: "Name", table: "Programmes"))
                                }
                                    .multilineTextAlignment(.trailing)
                            } label: {
                                Text(LocalizedStringResource("programmes.field.name", defaultValue: "Name", table: "Programmes"))
                            }
                        }
                        ConnectedCardDivider()
                        ConnectedCardRow {
                            LabeledContent {
                                TextField(
                                    text: $notes,
                                    prompt: Text(LocalizedStringResource("programmes.placeholder.optional", defaultValue: "Optional", table: "Programmes")),
                                    axis: .vertical
                                ) {
                                    Text(LocalizedStringResource("programmes.field.notes", defaultValue: "Notes", table: "Programmes"))
                                }
                                    .lineLimit(3, reservesSpace: true)
                                    .multilineTextAlignment(.trailing)
                            } label: {
                                Text(LocalizedStringResource("programmes.field.notes", defaultValue: "Notes", table: "Programmes"))
                            }
                        }
                        ConnectedCardDivider()
                        ConnectedCardRow {
                            Picker(selection: $mode) {
                                ForEach(ProgramMode.allCases) { mode in
                                    Text(mode.titleResource).tag(mode)
                                }
                            } label: {
                                Text(LocalizedStringResource("programmes.field.schedule", defaultValue: "Schedule", table: "Programmes"))
                            }
                        }
                        ConnectedCardDivider()
                        ConnectedCardRow {
                            DatePicker(selection: $startDate, displayedComponents: .date) {
                                Text(LocalizedStringResource("programmes.field.startDate", defaultValue: "Start Date", table: "Programmes"))
                            }
                        }
                        ConnectedCardDivider()
                        ConnectedCardRow {
                            Toggle(isOn: $isActive) {
                                Text(LocalizedStringResource("programmes.field.setActive", defaultValue: "Set Active", table: "Programmes"))
                            }
                        }
                    }
                }

                CardRowContainer {
                    Text(LocalizedStringResource("programmes.editor.structureHint", defaultValue: "New programmes start as a continuous workout rotation. You can keep that simple setup or switch into blocks later if you want phases.", table: "Programmes"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeaderView(resourceTitle: LocalizedStringResource("programmes.section.progression", defaultValue: "Progression", table: "Programmes"))
                    ConnectedCardSection {
                        ConnectedCardRow {
                            Picker(selection: $selectedProgressionProfileId) {
                                Text(LocalizedStringResource("programmes.value.none", defaultValue: "None", table: "Programmes")).tag(Optional<UUID>.none)
                                ForEach(progressionService.profiles, id: \.id) { profile in
                                    Text(verbatim: profile.name).tag(Optional(profile.id))
                                }
                            } label: {
                                Text(LocalizedStringResource("programmes.field.defaultProfile", defaultValue: "Default Profile", table: "Programmes"))
                            }
                        }
                        ConnectedCardDivider()
                        ConnectedCardRow {
                            Text(LocalizedStringResource("programmes.editor.progressionHint", defaultValue: "Programme-started sessions will use this profile for exercises that do not already have their own saved override.", table: "Programmes"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if mode == .continuous {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeaderView(resourceTitle: LocalizedStringResource("programmes.section.continuousSchedule", defaultValue: "Continuous Schedule", table: "Programmes"))
                        ConnectedCardSection {
                            ConnectedCardRow {
                                Stepper(
                                    String(localized: LocalizedStringResource("programmes.field.trainDaysBeforeRest", defaultValue: "Train Days Before Rest: \(trainDaysBeforeRest)", table: "Programmes")),
                                    value: $trainDaysBeforeRest,
                                    in: 1...14
                                )
                            }
                            ConnectedCardDivider()
                            ConnectedCardRow {
                                Stepper(
                                    String(localized: LocalizedStringResource("programmes.field.restDays", defaultValue: "Rest Days: \(restDays)", table: "Programmes")),
                                    value: $restDays,
                                    in: 0...7
                                )
                            }
                        }
                    }
                }
            }
            .screenContentPadding()
        }
        .appBackground()
        .navigationTitle(String(localized: program == nil
                                ? LocalizedStringResource("programmes.editor.newProgramme", defaultValue: "New Programme", table: "Programmes")
                                : LocalizedStringResource("programmes.editor.editProgramme", defaultValue: "Edit Programme", table: "Programmes")))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Text(LocalizedStringResource("programmes.action.cancel", defaultValue: "Cancel", table: "Programmes"))
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    saveProgram()
                } label: {
                    Text(LocalizedStringResource("programmes.action.save", defaultValue: "Save", table: "Programmes"))
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

            onSave?(program)
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

            onSave?(program)
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeaderView(resourceTitle: LocalizedStringResource("programmes.section.block", defaultValue: "Block", table: "Programmes"))
                    ConnectedCardSection {
                        ConnectedCardRow {
                            LabeledContent {
                                TextField(
                                    text: $name,
                                    prompt: Text(LocalizedStringResource("programmes.placeholder.optional", defaultValue: "Optional", table: "Programmes"))
                                ) {
                                    Text(LocalizedStringResource("programmes.field.name", defaultValue: "Name", table: "Programmes"))
                                }
                                    .multilineTextAlignment(.trailing)
                            } label: {
                                Text(LocalizedStringResource("programmes.field.name", defaultValue: "Name", table: "Programmes"))
                            }
                        }
                        ConnectedCardDivider()
                        ConnectedCardRow {
                            Toggle(isOn: $repeatsForever) {
                                Text(LocalizedStringResource("programmes.field.repeatForever", defaultValue: "Repeat Forever", table: "Programmes"))
                            }
                        }
                        if !repeatsForever {
                            ConnectedCardDivider()
                            ConnectedCardRow {
                                Stepper(durationLabel, value: $durationCount, in: 1...24)
                            }
                        }
                    }
                }

                if let previousBlock, !previousBlock.workouts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeaderView(resourceTitle: LocalizedStringResource("programmes.section.copyPreviousBlock", defaultValue: "Copy Previous Block", table: "Programmes"))
                        ConnectedCardSection {
                            ConnectedCardRow {
                                Toggle(isOn: $copyPreviousBlock) {
                                    Text(LocalizedStringResource("programmes.field.copyWorkoutsFrom", defaultValue: "Copy workouts from \(previousBlock.displayName)", table: "Programmes"))
                                }
                            }
                            ConnectedCardDivider()
                            ConnectedCardRow {
                                Text(LocalizedStringResource("programmes.editor.copyPreviousBlockHint", defaultValue: "This copies the routines and workout order so you can tweak the next phase instead of rebuilding it from scratch.", table: "Programmes"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .screenContentPadding()
        }
        .appBackground()
        .navigationTitle(String(localized: LocalizedStringResource("programmes.editor.newBlock", defaultValue: "New Block", table: "Programmes")))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Text(LocalizedStringResource("programmes.action.cancel", defaultValue: "Cancel", table: "Programmes"))
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
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
                } label: {
                    Text(LocalizedStringResource("programmes.action.save", defaultValue: "Save", table: "Programmes"))
                }
            }
        }
    }

    private var durationLabel: String {
        switch program.mode {
        case .weekly:
            return String(localized: LocalizedStringResource("programmes.field.weeks", defaultValue: "Weeks: \(durationCount)", table: "Programmes"))
        case .continuous:
            return String(localized: LocalizedStringResource("programmes.field.fullSplits", defaultValue: "Full Splits: \(durationCount)", table: "Programmes"))
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                SectionHeaderView(resourceTitle: LocalizedStringResource("programmes.section.workout", defaultValue: "Workout", table: "Programmes"))
                ConnectedCardSection {
                    if routineService.routines.isEmpty {
                        ConnectedCardRow {
                            Text(LocalizedStringResource("programmes.workoutEditor.noRoutines", defaultValue: "Create a routine first, then come back and attach it to this workout slot.", table: "Programmes"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ConnectedCardRow {
                            Picker(selection: $selectedRoutineId) {
                                ForEach(routineService.routines, id: \.id) { routine in
                                    Text(verbatim: routine.name).tag(Optional(routine.id))
                                }
                            } label: {
                                Text(LocalizedStringResource("programmes.field.routine", defaultValue: "Routine", table: "Programmes"))
                            }
                        }
                    }

                    ConnectedCardDivider()

                    ConnectedCardRow {
                        LabeledContent {
                            TextField(
                                text: $customName,
                                prompt: Text(LocalizedStringResource("programmes.placeholder.optional", defaultValue: "Optional", table: "Programmes"))
                            ) {
                                Text(LocalizedStringResource("programmes.field.customName", defaultValue: "Custom Name", table: "Programmes"))
                            }
                                .multilineTextAlignment(.trailing)
                        } label: {
                            Text(LocalizedStringResource("programmes.field.customName", defaultValue: "Custom Name", table: "Programmes"))
                        }
                    }

                    if block.program.mode == .weekly {
                        ConnectedCardDivider()
                        ConnectedCardRow {
                            Picker(selection: $selectedWeekday) {
                                ForEach(ProgramWeekday.allCases) { weekday in
                                    Text(verbatim: weekday.title).tag(weekday)
                                }
                            } label: {
                                Text(LocalizedStringResource("programmes.field.day", defaultValue: "Day", table: "Programmes"))
                            }
                        }
                    }
                }
            }
            .screenContentPadding()
        }
        .appBackground()
        .navigationTitle(String(localized: LocalizedStringResource("programmes.action.addWorkout", defaultValue: "Add Workout", table: "Programmes")))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Text(LocalizedStringResource("programmes.action.cancel", defaultValue: "Cancel", table: "Programmes"))
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    let trimmedName = customName.trimmingCharacters(in: .whitespacesAndNewlines)
                    _ = programService.addWorkout(
                        to: block,
                        routine: selectedRoutine,
                        name: trimmedName.isEmpty ? nil : trimmedName,
                        weekdayIndex: block.program.mode == .weekly ? selectedWeekday.rawValue : nil
                    )
                    dismiss()
                } label: {
                    Text(LocalizedStringResource("programmes.action.save", defaultValue: "Save", table: "Programmes"))
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
