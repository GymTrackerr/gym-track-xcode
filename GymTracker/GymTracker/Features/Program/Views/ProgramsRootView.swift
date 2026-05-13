//
//  ProgramsRootView.swift
//  GymTracker
//
//  Created by Codex on 2026-04-19.
//

import SwiftUI

struct ProgramsRootView: View {
    private struct OpenedProgramTarget: Identifiable, Hashable {
        let programId: UUID

        var id: UUID { programId }
    }

    private struct OpenedRoutineTarget: Identifiable, Hashable {
        let routineId: UUID

        var id: UUID { routineId }
    }

    @EnvironmentObject private var programService: ProgramService
    @EnvironmentObject private var routineService: RoutineService
    @EnvironmentObject private var sessionService: SessionService

    @State private var showingCreateProgram = false
    @State private var openedSession: Session?
    @State private var openedProgramTarget: OpenedProgramTarget?
    @State private var openedRoutineTarget: OpenedRoutineTarget?

    private var visiblePrograms: [Program] {
        programService.programs.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive {
                return lhs.isActive && !rhs.isActive
            }
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp > rhs.timestamp
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    var body: some View {
        List {
            programsSection
            routinesSection
        }
        .cardListScreen()
        .appBackground()
        .navigationTitle(
            Text(
                LocalizedStringResource(
                    "programme.term.programme",
                    defaultValue: "Programme",
                    table: "Programmes",
                    comment: "The app section for training programmes"
                )
            )
        )
        .navigationDestination(item: $openedSession) { session in
            SingleSessionView(session: session)
                .appBackground()
        }
        .navigationDestination(item: $openedProgramTarget) { target in
            if let program = programService.programs.first(where: { $0.id == target.programId }) ??
                programService.archivedPrograms.first(where: { $0.id == target.programId }) {
                ProgramDetailView(program: program)
                .appBackground()
            } else {
                EmptyView()
            }
        }
        .navigationDestination(item: $openedRoutineTarget) { target in
            if let routine = routineService.routines.first(where: { $0.id == target.routineId }) ??
                routineService.archivedRoutines.first(where: { $0.id == target.routineId }) {
                SingleDayView(routine: routine)
                    .appBackground()
            } else {
                EmptyView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    ProgressionProfilesView()
                        .appBackground()
                } label: {
                    Label {
                        Text("Progression", tableName: "Programmes")
                    } icon: {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreateProgram = true
                } label: {
                    Label {
                        Text("Add Programme", tableName: "Programmes")
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingCreateProgram) {
            NavigationStack {
                ProgramEditorSheet(program: nil) { program in
                    DispatchQueue.main.async {
                        openedProgramTarget = OpenedProgramTarget(programId: program.id)
                    }
                }
            }
            .editorSheetPresentation()
        }
        .sheet(isPresented: $routineService.editingSplit) {
            NavigationStack {
                RoutineCreateSheetView()
            }
            .editorSheetPresentation()
        }
        .onAppear {
            programService.loadPrograms()
            routineService.loadSplitDays()
            sessionService.loadSessions()
        }
    }

    private var programsSection: some View {
        Section {
//            sectionHeader(
//                title: "Programmes",
//                subtitle: "Keep one programme active, see the next workout, and jump straight into it."
//            )

            if programService.programs.isEmpty {
                emptyCard(
                    title: "No programmes yet",
                    subtitle: "Create a simple weekly or continuous programme and layer it on top of your existing routines."
                )
                .cardListRowStyle()
            } else {
                ForEach(visiblePrograms, id: \.id) { program in
                    let state = programService.resolvedState(
                        for: program,
                        sessions: sessionService.sessions
                    )
                    let workoutCount = programService.workoutCount(for: program)
                    let nextDueSummary = programService.nextDueSummary(
                        for: program,
                        sessions: sessionService.sessions
                    )

                    if program.isActive {
                        VStack(alignment: .leading, spacing: 12) {
                            Button {
                                openedProgramTarget = OpenedProgramTarget(programId: program.id)
                            } label: {
                                ActiveProgrammeCard(
                                    program: program,
                                    state: state,
                                    nextDueSummary: nextDueSummary
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                openSession(for: program, state: state)
                            } label: {
                                Label {
                                    Text(programActionTitleResource(state.actionTitle))
                                } icon: {
                                    Image(systemName: state.activeSession == nil ? "play.fill" : "arrow.clockwise")
                                }
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canLaunchWorkout(from: state))
                        }
                        .cardListRowContentPadding()
                        .cardListRowStyle()
                    } else {
                        Button {
                            openedProgramTarget = OpenedProgramTarget(programId: program.id)
                        } label: {
                            InactiveProgrammePreviewCard(
                                program: program,
                                workoutCount: workoutCount
                            )
                        }
                        .buttonStyle(.plain)
                        .cardListRowStyle()
                    }
                }
            }
        }
    }

    private var routinesSection: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Routines", tableName: "Programmes")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("These stay directly startable and are also the building blocks for programmes.", tableName: "Programmes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    routineService.editingContent = ""
                    routineService.editingSplit = true
                } label: {
                    Label {
                        Text("Add", tableName: "Programmes")
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
                .buttonStyle(.bordered)
            }
            .dashboardHeaderRowStyle()

            if routineService.routines.isEmpty {
                emptyCard(
                    title: "No routines yet",
                    subtitle: "Create a routine first if you want to attach workouts to a programme."
                )
                .cardListRowStyle()
            } else {
                ForEach(routineService.routines, id: \.id) { routine in
                    Button {
                        openedRoutineTarget = OpenedRoutineTarget(routineId: routine.id)
                    } label: {
                        ProgrammeDashboardRoutineCard(routine: routine)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            openedRoutineTarget = OpenedRoutineTarget(routineId: routine.id)
                        } label: {
                            Label {
                                Text(LocalizedStringResource("routines.action.edit", defaultValue: "Edit", table: "Routines"))
                            } icon: {
                                Image(systemName: "pencil")
                            }
                        }

                        Button(role: .destructive) {
                            routineService.removeSplitDay(routine)
                        } label: {
                            let isArchive = routineService.willArchiveOnDelete(routine)
                            Label {
                                Text(isArchive
                                     ? LocalizedStringResource("routines.action.archive", defaultValue: "Archive", table: "Routines")
                                     : LocalizedStringResource("routines.action.delete", defaultValue: "Delete", table: "Routines"))
                            } icon: {
                                Image(systemName: isArchive ? "archivebox" : "trash")
                            }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        let isArchive = routineService.willArchiveOnDelete(routine)
                        Button(role: .destructive) {
                            routineService.removeSplitDay(routine)
                        } label: {
                            Label {
                                Text(isArchive
                                     ? LocalizedStringResource("routines.action.archive", defaultValue: "Archive", table: "Routines")
                                     : LocalizedStringResource("routines.action.delete", defaultValue: "Delete", table: "Routines"))
                            } icon: {
                                Image(systemName: isArchive ? "archivebox" : "trash")
                            }
                        }
                    }
                    .cardListRowStyle()
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title, tableName: "Programmes")
                .font(.title3)
                .fontWeight(.semibold)
            Text(subtitle, tableName: "Programmes")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func emptyCard(title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title, tableName: "Programmes")
                .font(.headline)
            Text(subtitle, tableName: "Programmes")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardListRowContentPadding()
    }

    private func canLaunchWorkout(from state: ProgramResolvedState) -> Bool {
        state.canStartNextWorkout
    }

    private func openSession(for program: Program, state: ProgramResolvedState) {
        if !program.isActive {
            programService.setActive(program)
        }

        if let activeSession = state.activeSession {
            openedSession = activeSession
            return
        }

        guard let workout = state.nextWorkout else { return }
        openedSession = sessionService.startProgramWorkout(program: program, workout: workout)
    }

    private func programActionTitleResource(_ title: String) -> LocalizedStringResource {
        switch title {
        case "Add Workout":
            return LocalizedStringResource("programmes.action.addWorkout", defaultValue: "Add Workout", table: "Programmes")
        case "Workout Complete":
            return LocalizedStringResource("programmes.action.workoutComplete", defaultValue: "Workout Complete", table: "Programmes")
        case "Resume Current Workout":
            return LocalizedStringResource("programmes.action.resumeCurrentWorkout", defaultValue: "Resume Current Workout", table: "Programmes")
        case "Start Next Workout":
            return LocalizedStringResource("programmes.action.startNextWorkout", defaultValue: "Start Next Workout", table: "Programmes")
        default:
            return LocalizedStringResource(
                "programmes.action.open",
                defaultValue: "Open Programme",
                table: "Programmes",
                comment: "Fallback programme action title"
            )
        }
    }
}

private struct ProgrammeDashboardRoutineCard: View {
    let routine: Routine

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: routine.name)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(
                    LocalizedStringResource(
                        "programmes.routine.exerciseCount",
                        defaultValue: "\(routine.exerciseSplits.count) exercises",
                        table: "Programmes",
                        comment: "Number of exercises in a routine"
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .cardListRowContentPadding()
    }
}

private struct ActiveProgrammeCard: View {
    let program: Program
    let state: ProgramResolvedState
    let nextDueSummary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(verbatim: program.name)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if program.isActive {
                    Text("ACTIVE", tableName: "Programmes")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.14))
                        .clipShape(Capsule())
                }

                Spacer()
            }

            detailRow(title: "Schedule", value: state.scheduleLabel)
            detailRow(title: "Next Due", value: nextDueSummary)
            detailRow(title: "Next Workout", value: state.nextWorkoutLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func detailRow(title: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title, tableName: "Programmes")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct InactiveProgrammePreviewCard: View {
    let program: Program
    let workoutCount: Int

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: program.name)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(
                    LocalizedStringResource(
                        "programmes.workout.count",
                        defaultValue: "\(workoutCount) workouts",
                        table: "Programmes",
                        comment: "Number of workouts in a programme"
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .cardListRowContentPadding()
    }
}

private extension View {
    func dashboardHeaderRowStyle() -> some View {
        listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 4, trailing: 16))
    }
}

private struct RoutineCreateSheetView: View {
    @EnvironmentObject private var routineService: RoutineService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                SectionHeaderView(title: "Routine", tableName: "Programmes")
                ConnectedCardSection {
                    ConnectedCardRow {
                        LabeledContent {
                            TextField(text: $routineService.editingContent, prompt: Text("Required", tableName: "Programmes")) {
                                Text("Required", tableName: "Programmes")
                            }
                                .multilineTextAlignment(.trailing)
                        } label: {
                            Text("Name", tableName: "Programmes")
                        }
                    }
                }
            }
            .screenContentPadding()
        }
        .appBackground()
        .navigationTitle(Text("New Routine", tableName: "Programmes"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    routineService.editingSplit = false
                    routineService.editingContent = ""
                    dismiss()
                } label: {
                    Text("Cancel", tableName: "Programmes")
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    _ = routineService.addSplitDay()
                    dismiss()
                } label: {
                    Text("Save", tableName: "Programmes")
                }
                .disabled(routineService.editingContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
