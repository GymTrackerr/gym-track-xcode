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
        for (_, exercise) in addingExercises.enumerated() {
            // if it has relationship already, dont do?
            addExercise(routine: routine, exercise: exercise)
        }
    }
    
    func addExercise(routine: Routine, exercise: Exercise)  {
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
    
    func removeExercise(routine:Routine, exercise: Exercise) {
        withAnimation {
            let esd = routine.exerciseSplits.first(where: { $0.exercise == exercise })
            if let esd = esd {
                modelContext.delete(esd)
                routine.exerciseSplits.removeAll { $0.id == esd.id }
            }
            try? modelContext.save()
        }
    }
    
    func removeExercise(routine:Routine, offsets: IndexSet) {
        print("ofset \(offsets)")
        
        withAnimation {
            DispatchQueue.main.async {
                let sortedSplits = routine.exerciseSplits.sorted { $0.order < $1.order }
                for index in offsets {
                    guard sortedSplits.indices.contains(index) else { continue }
                    let split = sortedSplits[index]
                    self.modelContext.delete(split)
                    routine.exerciseSplits.removeAll { $0.id == split.id }
                }
                
                try? self.modelContext.save()
                self.renumberExercises(routine: routine)
            }
        }
    }
    
    func moveExercise(routine: Routine, from source: IndexSet, to destination: Int) {
        var exercises = routine.exerciseSplits.sorted { $0.order < $1.order }
        
        exercises.move(fromOffsets: source, toOffset: destination)
        
        for (i, exercise) in exercises.enumerated() {
            exercise.order = i
        }

        try? modelContext.save()
    }
}
