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
    private let repository: RoutineRepositoryProtocol

    init(context: ModelContext, repository: RoutineRepositoryProtocol? = nil) {
        self.repository = repository ?? LocalRoutineRepository(modelContext: context)
        super.init(context: context)
    }
    
    func renumberExercises(routine: Routine) {
        try? repository.renumberExerciseSplits(in: routine)
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
        try? repository.saveChanges()
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
        _ = try? repository.addExercise(to: routine, exercise: exercise)
    }
    
    func saveChanges() {
        try? repository.saveChanges()
    }
    
    func removeExercise(routine:Routine, exercise: Exercise) {
        withAnimation {
            try? repository.removeExercise(from: routine, exercise: exercise)
        }
    }
    
    func removeExercise(routine: Routine, splitIds: [UUID]) {
        guard !splitIds.isEmpty else { return }
        
        withAnimation {
            try? repository.removeExerciseSplits(from: routine, splitIds: splitIds)
        }
    }
    
    func moveExercise(routine: Routine, from source: IndexSet, to destination: Int) {
        try? repository.moveExercises(in: routine, from: source, to: destination)
    }
    
    func addRestoredExerciseSplit(routine: Routine, exerciseSplit: ExerciseSplitDay) {
        do {
            try repository.reinsertExerciseSplit(exerciseSplit, into: routine)
        } catch {
            print("Failed to restore exercise split: \(error)")
        }
    }
}
