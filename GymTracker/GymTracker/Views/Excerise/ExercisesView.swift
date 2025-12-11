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
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Exercises")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("\(exerciseService.exercises.count) exercises")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            // Exercises List
            if exerciseService.exercises.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("No Exercises")
                        .font(.headline)
                    
                    Text("Create your first exercise")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(exerciseService.exercises, id: \.id) { exercise in
                        NavigationLink {
                            SingleExerciseView(exercise: exercise)
                        } label: {
                            SingleExerciseLabelView(exercise: exercise)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                                .padding(.vertical, 4)
                                .padding(.horizontal, 4)
                        )
//                        .padding(.horizontal, 16)
                    }
                    .onDelete(perform: exerciseService.removeExercise)
                }
                .listStyle(.plain)
            }
        }
//        .navigationTitle("Exercises")
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
                    Menu {
                        ForEach (ExerciseType.allCases, id: \.id) { exerciseType in
                            Button(exerciseType.name, action: { exerciseService.selectedExerciseType = exerciseType })
                        }
                   } label: {
                       Label("Exercise Type: \(exerciseService.selectedExerciseType.name)", systemImage: "chevron.down")
                   }
                    
                    Button {
                        _ = exerciseService.addExercise()
                    } label: {
                        Label("Save", systemImage: "plus.circle")
                            .font(.title2)
                            .padding()
                    }
                    .disabled(exerciseService.editingContent.trimmingCharacters(in: .whitespaces).isEmpty)
                    
                    Spacer()
                }
                .padding()
                .navigationTitle("Create New Exercise")
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

