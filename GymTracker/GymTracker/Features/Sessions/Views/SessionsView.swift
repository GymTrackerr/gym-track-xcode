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
//    var showBottomToolbar: Bool = true
    
    @Namespace private var transition
    @State private var showingNotesImport = false
    @State private var showingCreateSession = false
//    @State private var newSession = false

//    @State private var isEditing = false

    private var sortedSessions: [Session] {
        sessionService.sessions.sorted { $0.timestampDone > $1.timestampDone }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    showingCreateSession = true
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("New Session")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                    }
                }
                .buttonStyle(.plain)
                .padding()
                .frame(maxWidth: .infinity)
//                .background(
//                    RoundedRectangle(cornerRadius: 16)
//                        .fill(Color(.systemBackground))
//                        .shadow(color: .gray.opacity(0.2), radius: 4, y: 2)
//                )
                .glassEffect(in: .rect(cornerRadius: 16.0))

//                .padding()
            }

            if !sortedSessions.isEmpty {
                HStack {
                    Text("Previous Sessions")
                        .font(.headline)
                        .underline()
                        .padding(.top, 8)
                }
                
                VStack(spacing: 12) {
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
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                sessionService.removeSession(session: session)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                sessionService.removeSession(session: session)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .buttonStyle(.plain)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .glassEffect(in: .rect(cornerRadius: 16.0))
                    }
                }
            }
        }
//        .toolbar {
//#if os(iOS)
//            ToolbarItem(placement: .navigationBarTrailing) {
//                EditButton()
//            }
//#endif
//        }
        // https://nilcoalescing.com/blog/PresentingLiquidGlassSheetsInSwiftUI/
        // https://nilcoalescing.com/blog/SwiftUISearchEnhancementsIniOSAndiPadOS26/
/*
        .toolbar {
            if showBottomToolbar {
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Button("Import", systemImage: "doc.text") {
                        showingNotesImport = true
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("New", systemImage: "plus") {
                        showingCreateSession = true
                    }
                }
                .matchedTransitionSource(
                    id: "new", in: transition
                )
            }
        }*/
        .sheet(isPresented: $showingCreateSession) {
            CreateSessionSheetView(
                openedSession: $openedSession,
                isPresented: $showingCreateSession
            )
            .presentationDetents([.medium, .large])
//            .presentationDragIndicator(.visible)
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
    @EnvironmentObject var sessionService: SessionService
    @EnvironmentObject var splitDayService: RoutineService
    @Bindable var session: Session

    var body: some View {
        VStack {
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
//                        if let currentSession = session {
//                            Image(systemName: currentSession.routine == routine
//                                  ? "checkmark.circle.fill"
//                                  : "circle")
//                            .font(.title3)
//                            .foregroundStyle(currentSession.routine == routine ? .green : .gray.opacity(0.4))
//                        } else {
                            Image(systemName: sessionService.selected_splitDay == routine
                                  ? "checkmark.circle.fill"
                                  : "circle")
                            .font(.title3)
                            .foregroundStyle(sessionService.selected_splitDay == routine ? .green : .gray.opacity(0.4))
//                        }
                    }
                }
                .buttonStyle(.plain)
                
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemBackground))
                        .shadow(color: .gray.opacity(0.2), radius: 4, y: 2)
                )
                .padding(.horizontal)
                .padding(.vertical, 2)
            }
            
        }
    }
}

struct SessionSelectSplit : View {
    @EnvironmentObject var sessionService: SessionService
    @EnvironmentObject var splitDayService: RoutineService
//    @State var session: Session? = nil
//    @State var changingCurrent: Bool = false
//    @State var session: Session?
//    @Binding
    var body: some View {
        VStack {
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
                
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemBackground))
                        .shadow(color: .gray.opacity(0.2), radius: 4, y: 2)
                )
                .padding(.horizontal)
                .padding(.vertical, 2)
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
            // Header
            VStack(alignment: .leading, spacing: 12) {
                Text("New Session")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
//
                Text("Start from your active programme or pick a routine directly.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    if let activeProgram, let activeProgramState {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Active Programme")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .padding(.horizontal, 16)

                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(activeProgram.name)
                                            .font(.body)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.primary)
                                        Text(activeProgramState.blockLabel)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(activeProgramState.nextWorkoutLabel)
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
                                        Text(activeProgramState.actionTitle)
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(activeProgramState.activeSession == nil && activeProgramState.nextWorkout?.routine == nil)
                                }

                                HStack {
                                    Text(activeProgramState.progressLabel)
                                    Spacer()
                                    Text(activeProgramState.scheduleLabel)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .glassEffect(in: .rect(cornerRadius: 12.0))
                            .padding(.horizontal, 16)
                        }
                    }

                    // Split Day Selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Workout Split")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 16)
                        
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
                                        
                                        Text(routine.name)
                                            .font(.body)
                                            .fontWeight(.medium)
                                            .foregroundColor(.primary)
                                        
                                        Spacer()
                                    }
                                    .padding(12)
                                    .frame(maxWidth: .infinity)
                                    .glassEffect(in: .rect(cornerRadius: 12.0))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    // Notes Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 16)
                        
                        TextField("e.g., Feeling strong today, focus on form.", text: $sessionService.create_notes)
                            .padding(12)
                            .font(.body)
                            .frame(height: 80, alignment: .topLeading)
                            .glassEffect(in: .rect(cornerRadius: 12.0))
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 8)
            }
            
            Spacer()
            
            // Start Session Button
            VStack(spacing: 10) {
                Button {
                    openedSession = sessionService.addSession()
                    isPresented = false
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text(sessionService.selected_splitDay == nil ? "Start Empty Session" : "Start Session")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                
                Button {
                    isPresented = false
                    sessionService.resetCreationState()
                } label: {
                    Text("Cancel")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
//        .navigationTitle("New Session")

        }

//        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
//        .glassEffect(in: .rect(cornerRadi´us: 20.0))
    }
}
