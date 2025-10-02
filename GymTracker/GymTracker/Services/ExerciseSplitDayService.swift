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

    func renumberExercises(splitDay: SplitDay) {
        for (i, esd) in splitDay.exerciseSplits.enumerated() {
            esd.order = i
        }
        try? modelContext.save()
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
    
    func removeExercise(splitDay:SplitDay, offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let esd = splitDay.exerciseSplits[index]
                modelContext.delete(esd)
            }
        }
    }
    
    func moveExercise(splitDay: SplitDay, from source: IndexSet, to destination: Int) {
        withAnimation {
            splitDay.exerciseSplits.move(fromOffsets: source, toOffset: destination)
            renumberExercises(splitDay: splitDay)
        }
    }
}
