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

    var body: some View {
        VStack {
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

            
            if !sessionService.sessions.isEmpty {
                HStack {
                    Text("Previous Sessions")
                        .font(.headline)
                        .padding(.horizontal)
                        .underline()
                        .padding(.top, 8)
                }
                
                ForEach(sessionService.sessions.reversed(), id: \.self) { session in
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
                    // TODO: Figure out solution for scrollview
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
//                    .background(.ultraThinMaterial)
//                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
//                    .shadow(radius: 6, y: 3)

                    .glassEffect(in: .rect(cornerRadius: 16.0))

//                    .background(
//                        RoundedRectangle(cornerRadius: 16)
//                            .fill(Color(.systemBackground))
//                            .shadow(color: .gray.opacity(0.2), radius: 4, y: 2)
//                    )
//                    .padding(.horizontal)
                    
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

struct CreateSessionSheetView: View {
    @EnvironmentObject var sessionService: SessionService
    @EnvironmentObject var splitDayService: RoutineService
    @EnvironmentObject var programService: ProgramService
    @Binding var openedSession: Session?
    @Binding var isPresented: Bool

    @State private var mode: SessionStartMode = .freestyle
    @State private var selectedRoutineId: UUID?
    @State private var selectedProgramId: UUID?
    @State private var selectedProgramDayId: UUID?
    @State private var followsNextWorkoutSelection: Bool = true

    private enum SessionStartMode: String, CaseIterable, Identifiable {
        case freestyle = "Freestyle"
        case routine = "Routine"
        case program = "Program"

        var id: String { rawValue }
    }

    private var selectedProgram: Program? {
        programService.programs.first(where: { $0.id == selectedProgramId })
    }

    private var selectedProgramDay: ProgramDay? {
        selectedProgram?.programDays.first(where: { $0.id == selectedProgramDayId })
    }

    private var sortedProgramDays: [ProgramDay] {
        guard let selectedProgram else { return [] }
        return selectedProgram.programDays.sorted { lhs, rhs in
            if lhs.weekIndex != rhs.weekIndex { return lhs.weekIndex < rhs.weekIndex }
            if lhs.dayIndex != rhs.dayIndex { return lhs.dayIndex < rhs.dayIndex }
            return lhs.order < rhs.order
        }
    }

    private var canStart: Bool {
        switch mode {
        case .freestyle:
            return true
        case .routine:
            return selectedRoutineId != nil
        case .program:
            return selectedProgramDay?.routine != nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("New Session")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text("Choose freestyle, routine, or program workout")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Start Type")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 16)

                        Picker("Start Type", selection: $mode) {
                            ForEach(SessionStartMode.allCases) { item in
                                Text(item.rawValue).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                    }

                    if mode == .routine {
                        routineSelectionSection
                    } else if mode == .program {
                        programSelectionSection
                    }

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

            VStack(spacing: 10) {
                Button {
                    startSession()
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start Session")
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
                .disabled(!canStart)
                
                Button {
                    cancelAndDismiss()
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
        }
        .onAppear {
            if let preselectedRoutine = sessionService.selected_splitDay {
                mode = .routine
                selectedRoutineId = preselectedRoutine.id
            } else if let currentProgram = programService.currentProgram() {
                mode = .program
                selectedProgramId = currentProgram.id
                prepareAndSelectNextWorkout(for: currentProgram)
            }
        }
        .onReceive(programService.$programs) { _ in
            resyncProgramSelectionFromPublishedPrograms()
        }
    }

    private var routineSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Routine")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .padding(.horizontal, 16)

            VStack(spacing: 8) {
                ForEach(splitDayService.routines, id: \.id) { routine in
                    Button {
                        selectedRoutineId = (selectedRoutineId == routine.id) ? nil : routine.id
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selectedRoutineId == routine.id ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selectedRoutineId == routine.id ? .green : .gray.opacity(0.5))

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
    }

    private var programSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Program")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 10) {
                Picker("Program", selection: $selectedProgramId) {
                    Text("Select Program").tag(UUID?.none)
                    ForEach(programService.programs, id: \.id) { program in
                        Text(program.name).tag(Optional(program.id))
                    }
                }
                .onChange(of: selectedProgramId) { _, newProgramId in
                    guard let newProgramId,
                          let program = programService.programs.first(where: { $0.id == newProgramId }) else {
                        selectedProgramDayId = nil
                        return
                    }
                    prepareAndSelectNextWorkout(for: program)
                }

                if let program = selectedProgram {
                    let currentWorkout = programService.currentWorkout(for: program)
                    let nextWorkout = programService.nextScheduledDay(for: program)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Program: \(program.name)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if let currentWorkout {
                            Text("Current Workout: \(programService.displayWorkoutName(for: currentWorkout))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let nextWorkout {
                            Text("Next Workout: \(programService.displayWorkoutName(for: nextWorkout))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let progressText = programService.progressSummaryText(for: program) {
                            Text(progressText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let nextWorkout {
                    Button {
                        prepareAndSelectNextWorkout(for: program)
                    } label: {
                            Label("Use Next Workout: \(programService.displayWorkoutName(for: nextWorkout))", systemImage: "arrow.forward.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    }
                }

                if !sortedProgramDays.isEmpty {
                    Picker("Workout", selection: $selectedProgramDayId) {
                        Text("Select Workout").tag(UUID?.none)
                        ForEach(sortedProgramDays, id: \.id) { day in
                            Text("Week \(day.weekIndex + 1) · \(programService.displayWorkoutName(for: day))").tag(Optional(day.id))
                        }
                    }
                    .onChange(of: selectedProgramDayId) { _, newValue in
                        guard let program = selectedProgram else { return }
                        let nextWorkoutId = programService.nextScheduledDay(for: program)?.id
                        followsNextWorkoutSelection = (newValue == nextWorkoutId)
                    }
                }
            }
            .padding(12)
            .glassEffect(in: .rect(cornerRadius: 12.0))
            .padding(.horizontal, 16)
        }
    }

    private func startSession() {
        switch mode {
        case .freestyle:
            sessionService.selected_splitDay = nil
            openedSession = sessionService.addSession()
        case .routine:
            let routine = splitDayService.routines.first(where: { $0.id == selectedRoutineId })
            sessionService.selected_splitDay = routine
            openedSession = sessionService.addSession()
        case .program:
            guard let program = selectedProgram else { return }
            openedSession = programService.startProgramSession(
                for: program,
                preferredProgramDayId: selectedProgramDayId,
                notes: sessionService.create_notes,
                sessionService: sessionService
            )
            sessionService.create_notes = ""
            sessionService.selected_splitDay = nil
        }

        if openedSession != nil {
            isPresented = false
        }
    }

    private func cancelAndDismiss() {
        isPresented = false
        sessionService.create_notes = ""
        sessionService.selected_splitDay = nil
    }

    private func prepareAndSelectNextWorkout(for program: Program) {
        let prepared = programService.prepareScheduleForSessionStart(for: program)
        if let prepared {
            selectedProgramDayId = prepared.id
            followsNextWorkoutSelection = true
            return
        }
        selectedProgramDayId = programService.nextScheduledDay(for: program)?.id
        followsNextWorkoutSelection = true
    }

    private func resyncProgramSelectionFromPublishedPrograms() {
        if let selectedProgramId,
           programService.programs.contains(where: { $0.id == selectedProgramId }) == false {
            self.selectedProgramId = nil
            self.selectedProgramDayId = nil
            return
        }

        guard let selectedProgram else {
            return
        }

        if let selectedProgramDayId,
           selectedProgram.programDays.contains(where: { $0.id == selectedProgramDayId }) {
            if followsNextWorkoutSelection {
                let nextWorkoutId = programService.nextScheduledDay(for: selectedProgram)?.id
                if nextWorkoutId != selectedProgramDayId {
                    self.selectedProgramDayId = nextWorkoutId
                }
            }
            return
        }

        selectedProgramDayId = programService.nextScheduledDay(for: selectedProgram)?.id
        followsNextWorkoutSelection = true
    }
}
