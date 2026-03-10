//
//  SingleDayView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftUI

// TODO: manage feature with more than one exercise of the same type
// adding exercise UI needs to be updated to support
// backend needs to delete by ID, look at sessionExercises
// show "last completed split(/exercise)" in view - same in exercises
// and a "last edited"

struct SingleDayView: View {
    @EnvironmentObject var esdService: ExerciseSplitDayService
    @EnvironmentObject var exerciseService: ExerciseService
    @EnvironmentObject var splitDayService: RoutineService
    @Bindable var routine: Routine
    
    @State var searchResults: [Exercise] = []
    @State private var routineAliasDraft: String = ""
    @EnvironmentObject var toastManager: ActionToastManager
    @Environment(\.editMode) private var editMode

    var body: some View {
        VStack {
            if (editMode?.wrappedValue == .inactive){
                VStack(alignment: .leading) {
                    Text("Routine: \(routine.name)")
                    Text("Order: \(routine.order)")
                    Text("Date: \(routine.timestamp.formatted(date: .numeric, time: .omitted))")

                    if !routine.aliases.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(routine.aliases, id: \.self) { alias in
                                    Text(alias)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color(.systemGray5))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
                .padding()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Identity")
                        .font(.headline)
                        .padding(.horizontal)

                    TextField("Routine Name", text: $routine.name)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)

                    HStack(spacing: 8) {
                        TextField("Add alias", text: $routineAliasDraft)
                            .textFieldStyle(.roundedBorder)

                        Button("Add") {
                            addRoutineAlias()
                        }
                        .buttonStyle(.bordered)
                        .disabled(routineAliasDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal)

                    if !routine.aliases.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(routine.aliases, id: \.self) { alias in
                                    HStack(spacing: 4) {
                                        Text(alias)
                                            .font(.caption)
                                        Button {
                                            removeRoutineAlias(alias)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(.systemGray5))
                                    .clipShape(Capsule())
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            
            List {
                ForEach(routine.exerciseSplits.sorted { $0.order < $1.order }, id: \.id) { exerciseSplit in
                    NavigationLink {
                        SingleExerciseView(exercise: exerciseSplit.exercise)
                    } label: {
                        SingleExerciseLabelView(exercise: exerciseSplit.exercise, orderInSplit: exerciseSplit.order)
                            .id(exerciseSplit.order)
                    }
                }
                .onDelete(perform: removeExercise)
                .onMove(perform: moveExercise)
                
                /* */
                Section {
                    ForEach(routine.sessions.sorted { $0.timestamp < $1.timestamp }, id: \.id) { session in
                        NavigationLink {
                            SingleSessionView(session: session)
                        } label: {
                            SingleSessionLabelView(session: session)
                            //                            .id(exerciseSlit.order)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(routine.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationLink {
                    RoutineHistoryChartView(routine: routine)
                        .appBackground()
                } label: {
                    Label("Charts", systemImage: "chart.bar.xaxis")
                }
            }
            
        #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
        #endif
            ToolbarItem {
                Button {
                    exerciseService.editingContent = ""
                    performSearch()
                    esdService.addingExerciseSplit = true
                } label: {
                    Label("Add Exercise", systemImage: "plus.circle")
                }
            }
        }
        .sheet(isPresented: $esdService.addingExerciseSplit) {
            NavigationView {
                VStack(spacing: 16) {
                    TextField("Search or Create Exercise", text: $exerciseService.editingContent)
                        .textFieldStyle(.roundedBorder)
                        .padding()
//                    TextField("Name", text: $exerciseService.editingContent)
//                        .textFieldStyle(.roundedBorder)
//                        .padding(.horizontal)
                    
                    Button {
//                        with 
                        let exerciseNew = exerciseService.addExercise()
                        DispatchQueue.main.async {
                            if let exercise = exerciseNew {
                                addExerciseEditing(exercise: exercise)
                            }
                            
                        }
                    } label: {
                        Label("Add", systemImage: "plus.circle")
                            .font(.title2)
                            .padding()
                    }
                    .disabled(exerciseService.editingContent.trimmingCharacters(in: .whitespaces).isEmpty)
                    List {
                        ForEach(searchResults, id: \.id) { exercise in
                            Button(action: {
                                if esdService.showingMinusIcon(routine: routine, id: exercise.id) {
                                    removeExerciseEditing(exercise: exercise)
                                } else {
                                    addExerciseEditing(exercise: exercise)
                                }
                            }) {
                                HStack {
                                    // if it is already added AND not in split
                                    // if it is adding
                                    // if it in removing
                                    if esdService.showingMinusIcon(routine: routine, id:  exercise.id) {
                                        Image(systemName: "minus")
                                    } else {
                                        Image(systemName: "plus")
                                    }
                                    
                                    Text(exercise.name)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    Spacer()
                }
                .padding()
                .navigationTitle("Add Exercises")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            esdService.confirmEditing(routine: routine)
                            exerciseService.editingContent = ""
                        }
                    }
                
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            esdService.endEditing()
                            exerciseService.editingContent = ""
                            exerciseService.editingContent = ""

                        }
                    }
                }
                .onChange(of: exerciseService.editingContent) {
                    performSearch()
                }
            }
        }
    }

    func removeExerciseEditing(exercise: Exercise) {
        if (esdService.isInAdding(id: exercise.id)) {
            esdService.addingExercises.removeAll { $0.id == exercise.id }
            
        } else {
            esdService.removingExercises.append(exercise)
        }
    }
    
    func addExerciseEditing(exercise: Exercise) {
        if (esdService.isInRemoving(id: exercise.id)) {
            esdService.removingExercises.removeAll { $0.id == exercise.id }
        } else {
            esdService.addingExercises.append(exercise)
        }
    }
    func performSearch() {
        print("searching \(exerciseService.editingContent)")
        searchResults = exerciseService.search(query: exerciseService.editingContent)
    }
    func removeExercise(offsets: IndexSet) {
        let sortedSplits = routine.exerciseSplits.sorted { $0.order < $1.order }
        let splitIds = offsets.compactMap { index in
            sortedSplits.indices.contains(index) ? sortedSplits[index].id : nil
        }
        removeExerciseOptimistic(splitIds: splitIds)
    }
    
    func moveExercise(from source: IndexSet, to destination: Int) {
        withTransaction(Transaction(animation: .default)) {
            esdService.moveExercise(routine: routine, from: source, to: destination)
        }

//        esdService.moveExercise(routine: routine, from: source, to: destination)
    }

    private func addRoutineAlias() {
        let trimmed = routineAliasDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var aliases = routine.aliases
        if aliases.contains(where: { $0.compare(trimmed, options: .caseInsensitive) == .orderedSame }) {
            routineAliasDraft = ""
            return
        }

        aliases.append(trimmed)
        _ = splitDayService.setAliases(for: routine, aliases: aliases)
        routineAliasDraft = ""
    }

    private func removeRoutineAlias(_ alias: String) {
        let updated = routine.aliases.filter { $0 != alias }
        _ = splitDayService.setAliases(for: routine, aliases: updated)
    }

    private func removeExerciseOptimistic(splitIds: [UUID]) {
        let toRemove = routine.exerciseSplits.filter { split in
            splitIds.contains(split.id)
        }
        guard !toRemove.isEmpty else { return }

        esdService.removeExercise(routine: routine, splitIds: splitIds)

        let count = toRemove.count
        let noun = count == 1 ? "exercise" : "exercises"
        let removedItems = toRemove
        toastManager.add(
            message: "Remove \(count) \(noun) from routine?",
            intent: .undo,
            timeout: 4,
            onAction: {
                for split in removedItems {
                    esdService.addRestoredExerciseSplit(routine: routine, exerciseSplit: split)
                }
            }
        )
    }
}

struct SingleDayLabelView: View {
    @Bindable var routine: Routine
    
    var body : some View {
        ZStack {
            VStack(alignment: .leading) {
                Text(routine.name)
                HStack {
                    Text("Day #\(routine.order+1)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()
                    Text(routine.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
