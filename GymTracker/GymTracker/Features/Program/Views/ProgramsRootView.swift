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

    @EnvironmentObject private var programService: ProgramService
    @EnvironmentObject private var routineService: RoutineService
    @EnvironmentObject private var sessionService: SessionService

    @State private var showingCreateProgram = false
    @State private var openedSession: Session?
    @State private var openedProgramTarget: OpenedProgramTarget?

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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                programsSection
                routinesSection
            }
            .screenContentPadding()
        }
        .navigationTitle("Programme")
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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    ProgressionProfilesView()
                        .appBackground()
                } label: {
                    Label("Progression", systemImage: "chart.line.uptrend.xyaxis")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreateProgram = true
                } label: {
                    Label("Add Programme", systemImage: "plus")
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
        }
        .sheet(isPresented: $routineService.editingSplit) {
            NavigationStack {
                RoutineCreateSheetView()
            }
        }
        .onAppear {
            programService.loadPrograms()
            routineService.loadSplitDays()
            sessionService.loadSessions()
        }
    }

    private var programsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
//            sectionHeader(
//                title: "Programmes",
//                subtitle: "Keep one programme active, see the next workout, and jump straight into it."
//            )

            if programService.programs.isEmpty {
                emptyCard(
                    title: "No programmes yet",
                    subtitle: "Create a simple weekly or continuous programme and layer it on top of your existing routines."
                )
            } else {
                VStack(spacing: 12) {
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
                                NavigationLink {
                                    ProgramDetailView(program: program)
                                        .appBackground()
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
                                    Label(state.actionTitle, systemImage: state.activeSession == nil ? "play.fill" : "arrow.clockwise")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!canLaunchWorkout(from: state))
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        } else {
                            NavigationLink {
                                ProgramDetailView(program: program)
                                    .appBackground()
                            } label: {
                                InactiveProgrammePreviewCard(
                                    program: program,
                                    workoutCount: workoutCount
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var routinesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Routines")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("These stay directly startable and are also the building blocks for programmes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    routineService.editingContent = ""
                    routineService.editingSplit = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            if routineService.routines.isEmpty {
                emptyCard(
                    title: "No routines yet",
                    subtitle: "Create a routine first if you want to attach workouts to a programme."
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(routineService.routines, id: \.id) { routine in
                        NavigationLink {
                            SingleDayView(routine: routine)
                                .appBackground()
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(routine.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)

                                    Text("\(routine.exerciseSplits.count) exercise\(routine.exerciseSplits.count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
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
}

private struct ActiveProgrammeCard: View {
    let program: Program
    let state: ProgramResolvedState
    let nextDueSummary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(program.name)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if program.isActive {
                    Text("ACTIVE")
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
    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
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
                Text(program.name)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("\(workoutCount) workout\(workoutCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct RoutineCreateSheetView: View {
    @EnvironmentObject private var routineService: RoutineService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Routine") {
                TextField("Name", text: $routineService.editingContent)
            }
        }
        .navigationTitle("New Routine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    routineService.editingSplit = false
                    routineService.editingContent = ""
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    _ = routineService.addSplitDay()
                    dismiss()
                }
                .disabled(routineService.editingContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
