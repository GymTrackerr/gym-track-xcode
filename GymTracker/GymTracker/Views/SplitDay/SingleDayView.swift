//
//  SingleDayView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftUI

struct SingleDayView: View {
    @EnvironmentObject var exerciseSplitDayService: ExerciseSplitDayService
    @EnvironmentObject var exerciseService: ExerciseService
    @Bindable var splitDay: SplitDay
    
    @State var searchText = ""
    @State var searchResults: [Exercise] = []

    var body: some View {
        VStack {
            VStack(alignment: .leading) {
                Text("SplitDay: \(splitDay.name)")
                Text("Order: \(splitDay.order)")
                Text("Date: \(splitDay.timestamp.formatted(date: .numeric, time: .omitted))")
            }
            .padding()
            Spacer()
            List {
                ForEach(splitDay.exerciseSplits) { exerciseSplit in
                    NavigationLink {
                        SingleExerciseView(exercise: exerciseSplit.exercise)
                    } label: {
                        SingleExerciseLabelView(exercise: exerciseSplit.exercise)
                    }
                }
                .onDelete(perform: removeExercise)
                .onMove(perform: moveExercise)
            }
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
//                    searchResults = exerciseService.search(query: searchText)
                    exerciseSplitDayService.addingExerciseSplit = true
                } label: {
                    Label("Add Split Day", systemImage: "plus.circle")
                }
            }
        }
        .sheet(isPresented: $exerciseSplitDayService.addingExerciseSplit) {
            NavigationView {
                VStack(spacing: 16) {
                    TextField("Search Exercise", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .padding()
                    
                    List(exerciseService.exercises, id: \.id) { exercise in
                        Button(action: {
                            exerciseSplitDayService.addExercise(splitDay: splitDay, exercise: exercise)
                        }) {
                            Text(exercise.name)
                        }
                    }
                    .listStyle(.plain)
                    
                    Spacer()
                }
                .padding()
                .navigationTitle("Create New Split Day")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            exerciseSplitDayService.addingExerciseSplit = false
                            searchText = ""
                        }
                        Button("Done") {
                            exerciseSplitDayService.addingExerciseSplit = false
                            searchText = ""
                        }
                    }
                }
                .onChange(of: searchText) {
                    performSearch()
                }
            }
        }
    }

    func performSearch() {
        searchResults = exerciseService.search(query: searchText)
    }
    func removeExercise(offsets: IndexSet) {
        exerciseSplitDayService.removeExercise(splitDay: splitDay, offsets: offsets)
    }
    
    func moveExercise(from source: IndexSet, to destination: Int) {
        exerciseSplitDayService.moveExercise(splitDay: splitDay, from: source, to: destination)
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
