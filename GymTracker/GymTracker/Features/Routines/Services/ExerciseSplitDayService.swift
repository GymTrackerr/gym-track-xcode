//
//  ExerciseSplitDayService.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-02.
//

import SwiftUI
import SwiftData
import Combine
internal import CoreData

class ExerciseSplitDayService: ServiceBase, ObservableObject {
    @Published var addingExerciseSplit: Bool = false
    @Published var addingExercises: [Exercise] = []
    @Published var removingExercises: [Exercise] = []
    
    func renumberExercises(routine: Routine) {
        guard !routine.isBuiltIn else { return }
        let exercises = routine.exerciseSplits.sorted { $0.order < $1.order }
        
        for (i, exercise) in exercises.enumerated() {
            print("number \(i)")
            exercise.order = i
        }
        
        try? modelContext.save()
    }
    
    // helpers
    func showingMinusIcon(routine: Routine, id: UUID) -> Bool{
        // if in adding
        // if added and NOT in removing
        return (isInAdding(id: id) || (!isInRemoving(id: id) && isInSplit(routine: routine, id: id)))
    }
    
    func isInRemoving(id: UUID) -> Bool {
        return removingExercises.contains(where: { $0.id == id})
    }
    
    func isInAdding(id: UUID) -> Bool {
        return addingExercises.contains(where: { $0.id == id})
    }
    
    func isInSplit(routine: Routine, id: UUID) -> Bool {
        return routine.exerciseSplits.contains(where: { $0.exercise.id == id })
    }
    
    func endEditing() {
        addingExercises.removeAll()
        removingExercises.removeAll()
        addingExerciseSplit = false
    }
    
    func confirmEditing(routine: Routine) {
        guard !routine.isBuiltIn else {
            endEditing()
            return
        }
        // adding exercises
        for (_, exercise) in addingExercises.enumerated() {
            addExercise(routine: routine, exercise: exercise)
        }
        
        // removing exercises
        for (_, exercise) in removingExercises.enumerated() {
            removeExercise(routine: routine, exercise: exercise)
        }
        try? modelContext.save()
        endEditing()
        withAnimation {
            renumberExercises(routine: routine)
        }
    }
    
    func syncSplitWithSession(routine: Routine, session: Session) {
        guard !routine.isBuiltIn else { return }
        for (_, exerciseSplit) in routine.exerciseSplits.enumerated() {
            removeExercise(routine: routine, exercise: exerciseSplit.exercise)
        }
        
        for (_, exercise) in session.sessionEntries.enumerated() {
            // remove old exercises
            addExercise(routine: routine, exercise: exercise.exercise)
        }
        loadFeature()
    }
    
    func addExercises(routine: Routine) {
        guard !routine.isBuiltIn else { return }
        for (_, exercise) in addingExercises.enumerated() {
            // if it has relationship already, dont do?
            addExercise(routine: routine, exercise: exercise)
        }
    }
    
    func addExercise(routine: Routine, exercise: Exercise)  {
        guard !routine.isBuiltIn else { return }
        // adds relations automatically
        // TODO: why cant i just do the count? not order
        guard !routine.exerciseSplits.contains(where: { $0.exercise.id == exercise.id }) else { return }
        let newESD = ExerciseSplitDay(
            order: routine.exerciseSplits.count,
            routine: routine,
            exercise: exercise
        )
        
        modelContext.insert(newESD)
        routine.exerciseSplits.append(newESD)
    }
    
    func saveChanges() {
        try? modelContext.save()
    }
    
    func removeExercise(routine:Routine, exercise: Exercise) {
        guard !routine.isBuiltIn else { return }
        withAnimation {
            let esd = routine.exerciseSplits.first(where: { $0.exercise == exercise })
            if let esd = esd {
                // Just remove from relationship - don't hard-delete for undo support
                routine.exerciseSplits.removeAll { $0.id == esd.id }
            }
            try? modelContext.save()
        }
    }
    
    func removeExercise(routine: Routine, splitIds: [UUID]) {
        guard !routine.isBuiltIn else { return }
        guard !splitIds.isEmpty else { return }
        
        withAnimation {
            let validSplits = routine.exerciseSplits.filter { splitIds.contains($0.id) }
            for split in validSplits {
                // Just remove from relationship - don't hard-delete for undo support
                routine.exerciseSplits.removeAll { $0.id == split.id }
            }
            
            try? modelContext.save()
            renumberExercises(routine: routine)
        }
    }
    
    func moveExercise(routine: Routine, from source: IndexSet, to destination: Int) {
        guard !routine.isBuiltIn else { return }
        var exercises = routine.exerciseSplits.sorted { $0.order < $1.order }
        
        exercises.move(fromOffsets: source, toOffset: destination)
        
        for (i, exercise) in exercises.enumerated() {
            exercise.order = i
        }
        
        try? modelContext.save()
    }
    
    func addRestoredExerciseSplit(routine: Routine, exerciseSplit: ExerciseSplitDay) {
        guard !routine.isBuiltIn else { return }
        // Re-add the split back to the routine
        if !routine.exerciseSplits.contains(where: { $0.id == exerciseSplit.id }) {
            routine.exerciseSplits.append(exerciseSplit)
        }
        do {
            try modelContext.save()
            renumberExercises(routine: routine)
        } catch {
            print("Failed to restore exercise split: \(error)")
        }
    }
}
