//
//  SplitDaysView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftUI

// TODO: completion of sessions - similar to completion of sessionexercises
struct SessionsView: View {
    
    @EnvironmentObject var sessionService: SessionService
    @EnvironmentObject var splitDayService: RoutineService
    @EnvironmentObject var exerciseService: ExerciseService
    @EnvironmentObject var userService: UserService
    @Binding var openedSession: Session?
    
    @Namespace private var transition
    @State private var showingNotesImport = false
    @State private var showingCreateSession = false

    private var sortedSessions: [Session] {
        sessionService.sessions.sorted { $0.timestampDone > $1.timestampDone }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardRowContainer {
                Button {
                    showingCreateSession = true
                } label: {
                    Label {
                        Text(LocalizedStringResource("sessions.create.title", defaultValue: "New Session", table: "Sessions"))
                    } icon: {
                        Image(systemName: "plus.circle")
                    }
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            if !sortedSessions.isEmpty {
                SectionHeaderView(
                    resourceTitle: LocalizedStringResource("sessions.list.previousSessions", defaultValue: "Previous Sessions", table: "Sessions")
                )
                
                VStack(spacing: 8) {
                    ForEach(sortedSessions, id: \.id) { session in
                        NavigationLink {
                            SingleSessionView(session: session)
                                .appBackground()
                        } label: {
                            SingleSessionLabelView(session: session)
                                .foregroundColor(.primary)
                        }
                        .contextMenu {
                            Button {
                                openedSession = session
                            } label: {
                                Label {
                                    Text(LocalizedStringResource("sessions.action.edit", defaultValue: "Edit", table: "Sessions"))
                                } icon: {
                                    Image(systemName: "pencil")
                                }
                            }
                            Button(role: .destructive) {
                                sessionService.removeSession(session: session)
                            } label: {
                                Label {
                                    Text(LocalizedStringResource("sessions.action.delete", defaultValue: "Delete", table: "Sessions"))
                                } icon: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                sessionService.removeSession(session: session)
                            } label: {
                                Label {
                                    Text(LocalizedStringResource("sessions.action.delete", defaultValue: "Delete", table: "Sessions"))
                                } icon: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .cardRowContainerStyle()
                    }
                }
            }
        }
        .sheet(isPresented: $showingCreateSession) {
            CreateSessionSheetView(
                openedSession: $openedSession,
                isPresented: $showingCreateSession
            )
            .editorSheetPresentation()
            .navigationTransition(
                .zoom(sourceID: "info", in: transition)
            )
        }
        .navigationDestination(isPresented: $showingNotesImport) {
            NotesImportView(currentUserId: userService.currentUser?.id) {
                sessionService.loadSessions()
                splitDayService.loadSplitDays()
                exerciseService.loadExercises()
                showingNotesImport = false
            }
        }
        .navigationDestination(item: $openedSession) { session in
            SingleSessionView(session: session)
                .appBackground()
        }
    }
}


struct SessionSelectSplit2 : View {
    @EnvironmentObject var splitDayService: RoutineService
    @Bindable var session: Session

    var body: some View {
        VStack(spacing: 8) {
            ForEach(splitDayService.routines, id: \.id) { routine in
                Button {
                    print("updated splitday of session")

                    if (session.routine == routine) {
                        session.routine = nil
                    } else {
                        session.routine = routine
                    }
                } label: {
                    HStack {
                        Text(routine.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: session.routine == routine
                              ? "checkmark.circle.fill"
                              : "circle")
                            .font(.title3)
                            .foregroundStyle(session.routine == routine ? .green : .gray.opacity(0.4))
                    }
                }
                .buttonStyle(.plain)
                .cardRowContainerStyle()
            }
        }
    }
}

struct SessionSelectSplit : View {
    @EnvironmentObject var sessionService: SessionService
    @EnvironmentObject var splitDayService: RoutineService

    var body: some View {
        VStack(spacing: 8) {
            ForEach(splitDayService.routines, id: \.id) { routine in
                Button {
                    if (sessionService.selected_splitDay == routine) {
                        sessionService.selected_splitDay = nil
                    } else {
                        sessionService.selected_splitDay = routine
                    }
                } label: {
                    HStack {
                        Text(routine.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()

                        Image(systemName: sessionService.selected_splitDay == routine
                              ? "checkmark.circle.fill"
                              : "circle")
                        .font(.title3)
                        .foregroundStyle(sessionService.selected_splitDay == routine ? .green : .gray.opacity(0.4))
                    }
                }
                .buttonStyle(.plain)
                .cardRowContainerStyle()
            }
        }
    }
}

struct CreateSessionSheetView: View {
    @EnvironmentObject var sessionService: SessionService
    @EnvironmentObject var splitDayService: RoutineService
    @EnvironmentObject var programService: ProgramService
    @Binding var openedSession: Session?
    @Binding var isPresented: Bool

    private var activeProgram: Program? {
        programService.activeProgram
    }

    private var activeProgramState: ProgramResolvedState? {
        guard let activeProgram else { return nil }
        return programService.resolvedState(for: activeProgram, sessions: sessionService.sessions)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedStringResource("sessions.create.title", defaultValue: "New Session", table: "Sessions"))
                            .font(.title2.weight(.bold))

                        Text(LocalizedStringResource("sessions.create.subtitle", defaultValue: "Start from your active programme or pick a routine directly.", table: "Sessions"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let activeProgram, let activeProgramState {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeaderView(
                                resourceTitle: LocalizedStringResource("sessions.create.activeProgramme", defaultValue: "Active Programme", table: "Sessions")
                            )

                            CardRowContainer {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(alignment: .top, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(verbatim: activeProgram.name)
                                                .font(.body)
                                                .fontWeight(.semibold)
                                                .foregroundStyle(.primary)
                                            Text(verbatim: activeProgramState.blockLabel)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(verbatim: activeProgramState.nextWorkoutLabel)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Button {
                                            if let activeSession = activeProgramState.activeSession {
                                                openedSession = activeSession
                                                sessionService.resetCreationState()
                                            } else if let workout = activeProgramState.nextWorkout {
                                                openedSession = sessionService.startProgramWorkout(program: activeProgram, workout: workout)
                                            }
                                            isPresented = false
                                        } label: {
                                            Text(verbatim: activeProgramState.actionTitle)
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .disabled(activeProgramState.activeSession == nil && !activeProgramState.canStartNextWorkout)
                                    }

                                    HStack {
                                        Text(verbatim: activeProgramState.progressLabel)
                                        Spacer()
                                        Text(verbatim: activeProgramState.scheduleLabel)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeaderView(
                            resourceTitle: LocalizedStringResource("sessions.create.workoutSplit", defaultValue: "Workout Split", table: "Sessions")
                        )
                        
                        VStack(spacing: 8) {
                            ForEach(splitDayService.routines, id: \.id) { routine in
                                Button {
                                    if sessionService.selected_splitDay == routine {
                                        sessionService.selectRoutine(nil)
                                    } else {
                                        sessionService.selectRoutine(routine)
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: sessionService.selected_splitDay == routine
                                              ? "checkmark.circle.fill"
                                              : "circle")
                                        .font(.title3)
                                        .foregroundStyle(sessionService.selected_splitDay == routine ? .green : .gray.opacity(0.5))
                                        
                                        Text(verbatim: routine.name)
                                            .font(.body)
                                            .fontWeight(.medium)
                                            .foregroundColor(.primary)
                                        
                                        Spacer()
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .cardRowContainerStyle()
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeaderView(
                            resourceTitle: LocalizedStringResource("sessions.create.notes", defaultValue: "Notes", table: "Sessions")
                        )
                        
                        ConnectedCardSection {
                            ConnectedCardRow {
                                TextField(
                                    text: $sessionService.create_notes,
                                    prompt: Text(LocalizedStringResource("sessions.create.notes.placeholder", defaultValue: "e.g., Feeling strong today, focus on form.", table: "Sessions")),
                                    axis: .vertical
                                ) {
                                    Text(LocalizedStringResource("sessions.create.notes", defaultValue: "Notes", table: "Sessions"))
                                }
                                    .lineLimit(3...5)
                            }
                        }
                    }
                }
                .screenContentPadding()
            }
            
            VStack(spacing: 10) {
                Button {
                    openedSession = sessionService.addSession()
                    isPresented = false
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text(sessionService.selected_splitDay == nil
                             ? LocalizedStringResource("sessions.create.startEmpty", defaultValue: "Start Empty Session", table: "Sessions")
                             : LocalizedStringResource("sessions.create.start", defaultValue: "Start Session", table: "Sessions"))
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button {
                    isPresented = false
                    sessionService.resetCreationState()
                } label: {
                    Text(LocalizedStringResource("sessions.action.cancel", defaultValue: "Cancel", table: "Sessions"))
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
            }
            .padding(16)
        }
        .appBackground()
    }
}
