//
//  ExercisesView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftUI

// add new exercises
// add aliases to exercises
// assign split day to exercises

struct ExercisesView: View {
    @EnvironmentObject var exerciseService: ExerciseService

    var body : some View {
        List {
            ForEach(exerciseService.exercises, id: \.id) { exercise in
                NavigationLink {
                    SingleExerciseView(exercise: exercise)
                } label: {
                    SingleExerciseLabelView(exercise: exercise)
                }
            }
            
            .onDelete(perform: exerciseService.removeExercise)
        }

        .navigationTitle("Exercises")
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
#endif
            ToolbarItem {
                Button {
                    exerciseService.editingExercise = true
                } label: {
                    Label("Add Exercise", systemImage: "plus.circle")
                }
            }
        }
        .sheet(isPresented: $exerciseService.editingExercise) {
            NavigationView {
                VStack(spacing: 16) {
                    Text("Name your new exercise")
                        .font(.headline)
                    
                    TextField("Name", text: $exerciseService.editingContent)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                    
                    Button {
                        exerciseService.addExercise()
                    } label: {
                        Label("Save", systemImage: "plus.circle")
                            .font(.title2)
                            .padding()
                    }
                    .disabled(exerciseService.editingContent.trimmingCharacters(in: .whitespaces).isEmpty)
                    
                    Spacer()
                }
                .padding()
                .navigationTitle("Create New Split Day")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            exerciseService.editingExercise = false
                            exerciseService.editingContent = ""
                        }
                    }
                }
            }
        }
    }
}

struct SplitDaysDropdownSelection: View {
    @EnvironmentObject var splitDayService: SplitDayService

    var body : some View {
        
    }
}
