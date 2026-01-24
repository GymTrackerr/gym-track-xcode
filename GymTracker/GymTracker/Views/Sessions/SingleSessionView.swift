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
    @EnvironmentObject var splitDayService: SplitDayService

    @Bindable var session: Session
    @Environment(\.editMode) private var editMode
    @State var syncingSplit: Bool = false

    var body: some View {
        VStack {
            VStack(alignment: .leading, spacing: 8) {
                if (editMode?.wrappedValue == .inactive){
                    VStack(alignment: .leading, spacing: 4) {
                        // Day header
                        HStack {
                            if let splitDay = session.splitDay {
                                Text("Program Day: " + splitDay.name)
                                    .font(.title2)
                                    .fontWeight(.bold)
                            } else {
                                Text("Day #1")
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }
                            Spacer()
                        }
                        
                        // Date and time
                        HStack {
                            Text(session.timestamp.formatted(date: .long, time: .shortened))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        
                        // Notes if present
                        if (session.notes != "") {
                            HStack {
                                Text("Notes: \(session.notes)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                    }

                } else {
                    // TODO: work on the UI
                    VStack {
                        SessionSelectSplit()
                            .padding()
                            .onChange(of: sessionService.selected_splitDay?.id) { oldValue, newValue in
                                _ = sessionService.updateSessionToSplitDay(session: session)
                            }
                    }
                    VStack {
                        TextField("Notes", text: $session.notes)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal)

                        DatePicker("Date & Time", selection: $session.timestamp, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .onChange(of: session.timestamp) { oldValue, newValue in
                                // change done timestamp in reference to start time 
                                let duration = session.timestampDone.timeIntervalSince(oldValue)
                                session.timestampDone = newValue.addingTimeInterval(duration)
                            }

                        Text("Until")

                        DatePicker("Date & Time", selection: $session.timestampDone, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact)
                            .labelsHidden()
                    }


                    
                    if let splitDay = session.splitDay {
                        if syncingSplit==true {
                            VStack {
                                Text("Are you sure? This action will replace all exercises with those in this session.")
                            }
                            HStack {
                                Button {
                                    syncingSplit = false
                                } label: {
                                    Text("Cancel")
                                }
                                
                                Button {
                                    esdService.syncSplitWithSession(splitDay: splitDay, session: session)
                                    syncingSplit = false
                                    
                                } label: {
                                    Text("Confirm")
                                }
                            }
                        }
                        else {
                            Button {
                                syncingSplit = true
                            } label: {
                                Text("Sync Split with Session")
                            }
                        }
                        // TODO: actually let eitehr
                    } else {
                        if syncingSplit==false {
                            Button {
                                syncingSplit = true
                            } label: {
                                Text("Create new Split Day")
                            }
                        } else {
                            VStack {
                                Text("Name your new split day")
                                    .font(.headline)
                                
                                TextField("Name", text: $splitDayService.editingContent)
                                    .textFieldStyle(.roundedBorder)
                                    .padding(.horizontal)
                            }
                            HStack {
                                Button {
                                    syncingSplit=false
                                    splitDayService.editingSplit = false
                                    splitDayService.editingContent = ""
                                } label: {
                                    Text("Cancel")
                                }
                                
                                Button {
                                    let newSplit = splitDayService.addSplitDay()
                                    if let newSplit {
                                        sessionService.updateSessionToSplitDay(session: session, splitDay: newSplit)
                                        esdService.syncSplitWithSession(splitDay: newSplit, session: session)
                                    }
                                    
                                    syncingSplit = false
                                } label: {
                                    Text("Save")
                                }
                                .disabled(splitDayService.editingContent.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    }
                }
            }
            .padding()

            List {
                ForEach(session.sessionExercises.sorted { $0.order < $1.order }, id: \.id) { sessionExercise in
                    NavigationLink {
                        SessionExerciseView(sessionExercise: sessionExercise)
                    } label: {
                        HStack(spacing: 12) {
                            if (sessionExercise.isCompleted) {
                                Image(systemName: "checkmark.arrow.trianglehead.counterclockwise")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "square.and.pencil")
                                    .foregroundColor(.gray)
                            }
                            
                            SingleExerciseLabelView(exercise: sessionExercise.exercise, orderInSplit: sessionExercise.order)
                                .id(sessionExercise.order)
                            
                            Spacer()
//                            
//                            Image(systemName: "chevron.right")
//                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
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
                            seService.toggleCompletion(sessionExercise: sessionExercise)
                        } label: {
                            Label(
                                sessionExercise.isCompleted ? "Uncheck" : "Complete",
                                systemImage: sessionExercise.isCompleted ? "pencil.slash" : "checkmark"
                            )
                        }
                        .tint(sessionExercise.isCompleted ? .orange : .green)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: (editMode?.wrappedValue == .inactive)) {
                        Button {
                            seService.removeExercise(session: session, sessionExercise: sessionExercise)
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
        }
        
        .navigationTitle("Session \(session.timestamp.formatted(date: .numeric, time: .omitted))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
        #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
        #endif
            ToolbarItem {
                Button {
                    exerciseService.editingContent = ""
                    seService.addingExerciseSession = true
                } label: {
                    Label("Add Split Day", systemImage: "plus.circle")
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
}

struct SingleSessionLabelView: View {
    @Bindable var session: Session

    var body : some View {
        HStack {
            VStack(alignment: .leading) {
                Text(session.timestamp, format: Date.FormatStyle(date: .long, time: .shortened))
                
                HStack {
                    HStack {
                        Text("\(session.sessionExercises.count) Exercise\(session.sessionExercises.count > 1 || session.sessionExercises.count==0 ? "s" : "")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        
                        if let splitDay = session.splitDay {
                            Text("Split: \(splitDay.name)")
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

