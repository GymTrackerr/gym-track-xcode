//
//  ExerciseService.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftUI
import SwiftData
import Combine
internal import CoreData

class ExerciseService : ServiceBase, ObservableObject {
    @Published var exercises: [Exercise] = []
    @Published var editingContent: String = ""
    @Published var editingExercise: Bool = false
    @Published var selectedExerciseType: ExerciseType = ExerciseType.weight

    override func loadFeature() {
        self.loadSplitDays()
    }
    
    func loadSplitDays() {
        let descriptor = FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)])

        do {
            exercises = try modelContext.fetch(descriptor)
            // verify exercises
            for exercise in exercises {
                print("\(exercise.name) \(exercise.type)")
            }
        } catch {
            exercises = []
        }
    }
    
    func search(query: String) -> [Exercise] {
        print("searching exercise \(query)")
        guard !query.isEmpty else { return exercises }
        return exercises.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
    
    func addExercise() -> Exercise? {
        print("Adding")
        let trimmedName = editingContent.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return nil }
        
        let newItem = Exercise(name: trimmedName, type: selectedExerciseType)
        var failed = false
        
        withAnimation {
            modelContext.insert(newItem)
            
            do {
                try modelContext.save()
                // Clear and dismiss sheet after successful save
                editingExercise = false
                editingContent = ""
                loadSplitDays()
                selectedExerciseType = .weight

            } catch {
                print("Failed to save new split day: \(error)")
                failed=true
            }
        }
        
        if (failed==true) {
            return nil
        }
        return newItem;
    }
    
    func removeExercise(offsets: IndexSet) {
        print("not activating")
        withAnimation {
            for index in offsets {
                modelContext.delete(exercises[index])
            }

            do {
                try modelContext.save()
                loadSplitDays()
                
            } catch {
                print("Failed to save after deletion: \(error)")
            }
        }
    }
}

