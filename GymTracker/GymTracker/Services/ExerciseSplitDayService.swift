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
    //    @Published var addingExerciseIDs: Swift.Set<UUID> = []
    @Published var addingExercises: [Exercise] = []
    @Published var removingExercises: [Exercise] = []
    
    func renumberExercises(splitDay: SplitDay) {
        //        let exercises = Array(splitDay.exerciseSplits)
        let exercises = splitDay.exerciseSplits.sorted { $0.order < $1.order }
        
        for (i, exercise) in exercises.enumerated() {
            exercise.order = i
        }
        
        try? modelContext.save()
        //
        //        for (i, esd) in splitDay.exerciseSplits.enumerated() {
        //            esd.order = i
        //        }
        //        try? modelContext.save()
    }
    
    // helpers
    func showingMinusIcon(splitDay: SplitDay, id: UUID) -> Bool{
        // if in adding
        // if added and NOT in removing
        return (isInAdding(id: id) || (!isInRemoving(id: id) && isInSplit(splitDay: splitDay, id: id)))
    }
    func isInRemoving(id: UUID) -> Bool {
        return removingExercises.contains(where: { $0.id == id})
        
    }
    func isInAdding(id: UUID) -> Bool {
        return addingExercises.contains(where: { $0.id == id})
    }
    
    func isInSplit(splitDay: SplitDay, id: UUID) -> Bool {
        return splitDay.exerciseSplits.contains(where: { $0.exercise.id == id })
    }
    
    func endEditing() {
        addingExercises.removeAll()
        removingExercises.removeAll()
        addingExerciseSplit = false
    }
    
    func confirmEditing(splitDay: SplitDay) {
        // adding exercises
        for (_, exercise) in addingExercises.enumerated() {
            addExercise(splitDay: splitDay, exercise: exercise)
        }
        
        // removing exercises
        for (_, exercise) in removingExercises.enumerated() {
            removeExercise(splitDay: splitDay, exercise: exercise)
        }
        
        endEditing()
    }
    
    func addExercises(splitDay: SplitDay) {
        for (_, exercise) in addingExercises.enumerated() {
            // if it has relationship already, dont do?
            addExercise(splitDay: splitDay, exercise: exercise)
        }
    }
    
    func addExercise(splitDay: SplitDay, exercise: Exercise)  {
        // adds relations automatically
        let newESD = ExerciseSplitDay(
            order: (splitDay.exerciseSplits.last?.order ?? 0) + 1,
            splitDay: splitDay,
            exercise: exercise
        )
        
        modelContext.insert(newESD)
    }
    
    func removeExercise(splitDay:SplitDay, exercise: Exercise) {
        withAnimation {
            let esd = splitDay.exerciseSplits.first(where: { $0.exercise == exercise })!
            modelContext.delete(esd)
            try? modelContext.save()
            
            //            renumberExercises(splitDay: splitDay)
        }
    }
    
    func removeExercise(splitDay:SplitDay, offsets: IndexSet) {
        //        withAnimation {
        
        //        let exercises = Array(splitDay.exerciseSplits)
        withAnimation {
            
            for index in offsets {
                modelContext.delete(splitDay.exerciseSplits[index])
            }
            //        try? modelContext.save()
            
            //        let _ = Array(splitDay.exerciseSplits)
            
            //        withAnimation {
            renumberExercises(splitDay: splitDay)
        }
        /*
         for index in offsets {
         let exercise = splitDay.exerciseSplits[index].exercise
         
         removeExercise(splitDay: splitDay, exercise: exercise)
         }*/
    }
    
    func moveExercise(splitDay: SplitDay, from source: IndexSet, to destination: Int) {
        var exercises = splitDay.exerciseSplits.sorted { $0.order < $1.order }
        
        exercises.move(fromOffsets: source, toOffset: destination)
        
        for (index, exerciseSplit) in exercises.enumerated() {
            exerciseSplit.order = index
        }
        
        try? modelContext.save()
        /*
         withAnimation {
         var exercises = splitDay.exerciseSplits.sorted { $0.order < $1.order }
         
         
         //            sortedExer
         exercises.move(fromOffsets: source, toOffset: destination)
         
         
         renumberExercises(splitDay: splitDay)
         }
         */
    }
}

