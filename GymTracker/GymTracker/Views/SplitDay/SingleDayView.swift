//
//  SingleDayView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftUI

// TODO: FIX BUG
// BUG: swipe to delete doesnt delete proper
// and order doesnt update again when updating for some reason

// now seems to just be renumbering function not working nicely, not sure

struct SingleDayView: View {
    @EnvironmentObject var esdService: ExerciseSplitDayService
    @EnvironmentObject var exerciseService: ExerciseService
    @Bindable var splitDay: SplitDay
    
    @State var searchText = ""
    @State var searchResults: [Exercise] = []
//    @State var refreshTrigger: Bool = false

    var body: some View {
        VStack {
            VStack(alignment: .leading) {
                Text("SplitDay: \(splitDay.name)")
                Text("Order: \(splitDay.order)")
                Text("Date: \(splitDay.timestamp.formatted(date: .numeric, time: .omitted))")
            }
            .padding()
            
            List {
                ForEach(splitDay.exerciseSplits.sorted { $0.order < $1.order }, id: \.id) { exerciseSplit in
                    NavigationLink {
                        SingleExerciseView(exercise: exerciseSplit.exercise, orderInSplit: exerciseSplit.order)
                    } label: {
                        SingleExerciseLabelView(exercise: exerciseSplit.exercise, orderInSplit: exerciseSplit.order)
                            .id(exerciseSplit.order)
                    }
                }
                .onDelete(perform: removeExercise)
                .onMove(perform: moveExercise)
            }
//            .frame(maxHeight: .infinity)

//            .onChange(of: splitDay.exerciseSplits) {
//                refreshTrigger.toggle()
//            }

        }
        .navigationTitle(splitDay.name)
        .toolbar {
        #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
        #endif
            ToolbarItem {
                Button {
                    searchText = ""
                    performSearch()
                    esdService.addingExerciseSplit = true
                } label: {
                    Label("Add Split Day", systemImage: "plus.circle")
                }
            }
        }
        .sheet(isPresented: $esdService.addingExerciseSplit) {
            NavigationView {
                VStack(spacing: 16) {
                    TextField("Search Exercise", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .padding()
                    TextField("Name", text: $exerciseService.editingContent)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                    
                    Button {
//                        with 
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
                        ForEach(searchResults, id: \.id) { exercise in
                            Button(action: {
                                if esdService.showingMinusIcon(splitDay: splitDay, id: exercise.id) {
                                    removeExerciseEditing(exercise: exercise)
                                } else {
                                    addExerciseEditing(exercise: exercise)
                                }
                            }) {
                                HStack {
                                    // if it is already added AND not in split
                                    // if it is adding
                                    // if it in removing
                                    if esdService.showingMinusIcon(splitDay: splitDay, id:  exercise.id) {
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
                    Spacer()
                }
                .padding()
                .navigationTitle("Add Exercises")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            esdService.confirmEditing(splitDay: splitDay)
                            searchText = ""
                        }
                    }
                
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            esdService.endEditing()
                            searchText = ""
                            exerciseService.editingContent = ""

                        }
                    }
                }
                .onChange(of: searchText) {
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
        print("searching \(searchText)")
        searchResults = exerciseService.search(query: searchText)
    }
    func removeExercise(offsets: IndexSet) {
        esdService.removeExercise(splitDay: splitDay, offsets: offsets)
    }
    
    func moveExercise(from source: IndexSet, to destination: Int) {
        withTransaction(Transaction(animation: .default)) {
            esdService.moveExercise(splitDay: splitDay, from: source, to: destination)
        }

//        esdService.moveExercise(splitDay: splitDay, from: source, to: destination)
    }
}

struct SingleDayLabelView: View {
    @Bindable var splitDay: SplitDay
    
    var body : some View {
        ZStack {
            VStack(alignment: .leading) {
                Text(splitDay.name)
                HStack {
                    Text("Day #\(splitDay.order+1)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()
                    Text(splitDay.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

