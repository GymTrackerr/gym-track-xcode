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

            Section("From API") {
                ForEach(exerciseService.apiExercises, id: \.id) { apiExercise in
//                    HStack {
//                        AsyncImage(url: URL(string: "http://localhost:5002/v1/static\(apiExercise.images.first ?? "")")) { phase in
//                            switch phase {
//                            case .empty:
//                                ZStack {
//                                    Rectangle().fill(Color.gray.opacity(0.1))
//                                    ProgressView()
//                                }
//                            case .success(let image):
//                                image
//                                    .resizable()
//                                    .scaledToFill()
//                                    .frame(height: 120)
//                                    .clipped()
//                            case .failure:
//                                Rectangle()
//                                    .fill(Color.gray.opacity(0.1))
//                                    .overlay(Image(systemName: "photo").foregroundColor(.gray))
//                            @unknown default:
//                                EmptyView()
//                            }
//                        }
//                        .cornerRadius(12)
//
//                        VStack {
//                            
//                        }
//                    }
                    Text(apiExercise.name)
                        .foregroundColor(.secondary)
                }
            }
            
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
                    Menu {
                        ForEach (ExerciseType.allCases, id: \.id) { exerciseType in
                            Button(exerciseType.name, action: { exerciseService.selectedExerciseType = exerciseType })
                        }
                   } label: {
                       Label("Exercise Type: \(exerciseService.selectedExerciseType.name)", systemImage: "chevron.down")
//                           .padding()
//                           .background(Color.blue.opacity(0.1))
//                           .cornerRadius(8)
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

struct SplitDaysDropdownSelection: View {
    @EnvironmentObject var splitDayService: SplitDayService

    var body : some View {
        
    }
}
