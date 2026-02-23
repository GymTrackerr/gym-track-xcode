//
//  SingleDayView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftUI

// TODO: remove / add exercises from (+) menu

struct SingleSessionView: View {
    @EnvironmentObject var seService: SessionExerciseService
    @EnvironmentObject var esdService: ExerciseSplitDayService
    @EnvironmentObject var sessionService: SessionService
    @EnvironmentObject var exerciseService: ExerciseService
    @EnvironmentObject var splitDayService: RoutineService
    @EnvironmentObject var timerService: TimerService

    @Bindable var session: Session
    @Environment(\.editMode) private var editMode
    @State var syncingSplit: Bool = false

    private let cardCornerRadius: CGFloat = 16
    private let accentGreen = Color.green
    private let softGreen = Color.green.opacity(0.12)

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 16) {
                if editMode?.wrappedValue == .inactive {
                    sessionSummaryCard
                } else {
                    sessionEditCard
                }
            }
            .padding(.horizontal)
            .padding(.top, 6)

            VStack(alignment: .leading, spacing: 8) {
                Text("Today's Exercises")
                    .font(.headline)
                    .padding(.horizontal)

                List {
                    ForEach(session.sessionEntries.sorted { $0.order < $1.order }, id: \.id) { sessionEntry in
                        NavigationLink {
                            SessionExerciseView(sessionEntry: sessionEntry).appBackground()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: sessionEntry.isCompleted ? "checkmark.arrow.trianglehead.counterclockwise" : "square.and.pencil")
                                    .foregroundColor(sessionEntry.isCompleted ? .green : .secondary)
                                    .padding(.horizontal, 8)

                                VStack(alignment: .leading, spacing: 4) {
                                    SingleExerciseLabelView(exercise: sessionEntry.exercise, orderInSplit: sessionEntry.order)
                                        .id(sessionEntry.order)
                                }

                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                                .padding(.vertical, 4)
                                .padding(.horizontal, 4)
                        )
                        .swipeActions(edge: (editMode?.wrappedValue == .inactive) ? .leading : .trailing, allowsFullSwipe: (editMode?.wrappedValue == .inactive)) {
                            Button {
                                seService.toggleCompletion(sessionEntry: sessionEntry)
                            } label: {
                                Label(
                                    sessionEntry.isCompleted ? "Uncheck" : "Complete",
                                    systemImage: sessionEntry.isCompleted ? "pencil.slash" : "checkmark"
                                )
                            }
                            .tint(sessionEntry.isCompleted ? .orange : .green)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: (editMode?.wrappedValue == .inactive)) {
                            Button {
                                seService.removeExercise(session: session, sessionEntry: sessionEntry)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                    }
                    .onDelete(perform: removeExercise)
                    .onMove(perform: moveExercise)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .foregroundStyle(.primary)
        
        .navigationTitle(sessionTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
        #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
        #endif
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    TimerView().appBackground()
                } label: {
                    Label(timerButtonTitle, systemImage: "timer")
                }
            }
            ToolbarItem {
                Button {
                    exerciseService.editingContent = ""
                    seService.addingExerciseSession = true
                } label: {
                    Label("Add Exercise", systemImage: "plus.circle")
                }
            }
        }
        .sheet(isPresented: $seService.addingExerciseSession) {
            addingExerciseSessionView(session: session)
        }
    }
    
    func removeExercise(offsets: IndexSet) {
        seService.removeExercise(session: session, offsets: offsets)
    }
    
    func moveExercise(from source: IndexSet, to destination: Int) {
        withTransaction(Transaction(animation: .default)) {
            seService.moveExercise(session: session, from: source, to: destination)
        }
    }

    private var isSessionIncomplete: Bool {
        session.timestampDone == session.timestamp
    }

    private var isSessionCompleted: Bool {
        session.timestampDone != session.timestamp
    }

    private var sessionTitle: String {
        let dateStyle = Date.FormatStyle(date: .numeric, time: .omitted)
        return "Session \(session.timestamp.formatted(dateStyle))"
    }

    private var sessionTimeDetail: String {
        let dateStyle = Date.FormatStyle(date: .long, time: .omitted)
        let timeStyle = Date.FormatStyle(date: .omitted, time: .shortened)
        let dateText = session.timestamp.formatted(dateStyle)
        let startTime = session.timestamp.formatted(timeStyle)

        if isSessionCompleted {
            let endTime = session.timestampDone.formatted(timeStyle)
            return "\(dateText) at \(startTime) - \(endTime)"
        }

        return "\(dateText) at \(startTime)"
    }

    private var timerButtonTitle: String {
        if timerService.timer != nil {
            return "Timer \(timerService.formatted)"
        }

        return "Timer"
    }

    private var sessionSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let routine = session.routine {
                    Text(routine.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                } else {
                    Text("Day #1")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                Spacer()
            }

            Text(sessionTimeDetail)
                .font(.subheadline)
                .foregroundColor(.secondary)

            if isSessionIncomplete {
                Button {
                    session.timestampDone = Date()
                } label: {
                    Text("Finish Session")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(accentGreen)
            }

            if session.notes.trimmingCharacters(in: .whitespacesAndNewlines) != "" {
                Text(session.notes)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(softGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
        .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
    }

    private var sessionEditCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Session")
                .font(.headline)

            VStack(spacing: 12) {
                SessionSelectSplit()
                    .onChange(of: sessionService.selected_splitDay?.id) { _, _ in
                        _ = sessionService.updateSessionToSplitDay(session: session)
                    }

                TextField("Add optional notes...", text: $session.notes)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Start")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    DatePicker("Date & Time", selection: $session.timestamp, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .onChange(of: session.timestamp) { oldValue, newValue in
                            // Keep end time aligned with start time change.
                            let duration = session.timestampDone.timeIntervalSince(oldValue)
                            session.timestampDone = newValue.addingTimeInterval(duration)
                        }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("End")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    DatePicker("Date & Time", selection: $session.timestampDone, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .labelsHidden()
                }
            }

            sessionEditActionSection
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
        .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
    }

    private var sessionEditActionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let routine = session.routine {
                if syncingSplit {
                    Text("Are you sure? This action will replace all exercises with those in this session.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Button {
                            syncingSplit = false
                        } label: {
                            Text("Cancel")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            esdService.syncSplitWithSession(routine: routine, session: session)
                            syncingSplit = false
                        } label: {
                            Text("Confirm")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accentGreen)
                    }
                } else {
                    Button {
                        syncingSplit = true
                    } label: {
                        Text("Sync Routine with Session")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                if !syncingSplit {
                    Button {
                        syncingSplit = true
                    } label: {
                        Text("Create new Routine")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name your new split day")
                            .font(.subheadline)
                        TextField("Name", text: $splitDayService.editingContent)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack(spacing: 12) {
                        Button {
                            syncingSplit = false
                            splitDayService.editingSplit = false
                            splitDayService.editingContent = ""
                        } label: {
                            Text("Cancel")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            let newSplit = splitDayService.addSplitDay()
                            if let newSplit {
                                sessionService.updateSessionToSplitDay(session: session, routine: newSplit)
                                esdService.syncSplitWithSession(routine: newSplit, session: session)
                            }
                            syncingSplit = false
                        } label: {
                            Text("Save")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accentGreen)
                        .disabled(splitDayService.editingContent.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }
}

struct SingleSessionLabelView: View {
    @Bindable var session: Session

    var body : some View {
        HStack {
            VStack(alignment: .leading) {
                Text(session.timestamp, format: Date.FormatStyle(date: .long, time: .shortened))
                
                HStack {
                    HStack {
                        Text("\(session.sessionEntries.count) Exercise\(session.sessionEntries.count > 1 || session.sessionEntries.count==0 ? "s" : "")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        
                        if let routine = session.routine {
                            Text("Routine: \(routine.name)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            
            Image(systemName: "chevron.forward")
        }
    }
}


struct addingExerciseSessionView : View {
    @EnvironmentObject var seService: SessionExerciseService
    @EnvironmentObject var exerciseService: ExerciseService

    @State var searchResults: [Exercise] = []

    @Bindable var session: Session
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                TextField("Search or Create Exercise", text: $exerciseService.editingContent)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                Button {
                    let exerciseNew = exerciseService.addExercise()
                    DispatchQueue.main.async {
                        if let exercise = exerciseNew {
                            addExerciseEditing(exercise: exercise)
                        }
                        
                    }
                } label: {
                    Label("Save", systemImage: "plus.circle")
                        .font(.title2)
                        .padding()
                }
                .disabled(exerciseService.editingContent.trimmingCharacters(in: .whitespaces).isEmpty)
                List {
                    // TODO: ADD BUTTONS TO ADD/REMOVE EXERCISES?? -- make sure there are no sets/reps
                    ForEach(searchResults, id: \.id) { exercise in
                        Button(action: {
                            addExerciseEditing(exercise: exercise)
                        }) {
                            HStack {
                                Text("\(seService.amountAdded(session: session, exercise: exercise))")

                                Image(systemName: "plus")

                                Text(exercise.name)
                            }
                        }
                    }
                }

                .listStyle(.plain)
                Spacer()
            }
            .padding()
            .navigationTitle("Add Exercises")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        seService.confirmEditing(session: session)
                        exerciseService.editingContent = ""
                    }
                }
            
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        seService.endEditing()
                        exerciseService.editingContent = ""
                        exerciseService.editingContent = ""
                    }
                }
            }
            .onChange(of: exerciseService.editingContent) {
                performSearch()
            }
        }
        .onAppear {
            performSearch()
        }
    }
//    func removeExerciseEditing(exercise: Exercise) {
//        if (seService.isInAdding(id: exercise.id)) {
//            seService.addingExercises.removeAll { $0.id == exercise.id }
//            
//        } else {
//            seService.removingExercises.append(exercise)
//        }
//    }
    
    func addExerciseEditing(exercise: Exercise) {
        if (seService.isInRemoving(id: exercise.id)) {
            seService.removingExercises.removeAll { $0.id == exercise.id }
        } else {
            seService.addingExercises.append(exercise)
        }
    }
    
    func performSearch() {
        print("searching \(exerciseService.editingContent)")
        searchResults = exerciseService.search(query: exerciseService.editingContent)
    }
}
