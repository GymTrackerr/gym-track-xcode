//
//  SessionExerciseService.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-05.
//

import SwiftUI
import SwiftData
import Combine
internal import CoreData

class SessionExerciseService: ServiceBase, ObservableObject {
    @Published var addingExerciseSession: Bool = false
    @Published var addingExercises: [Exercise] = []
    @Published var removingExercises: [SessionExercise] = []
    
    func renumberExercises(session: Session) {
        let exercises = session.sessionExercises.sorted { $0.order < $1.order }
        
        for (i, exercise) in exercises.enumerated() {
            print("number \(i)")
            exercise.order = i
        }
        
        try? modelContext.save()
    }

    func toggleCompletion(sessionExercise: SessionExercise) {
        withAnimation {
            sessionExercise.isCompleted.toggle()
            try? modelContext.save()
        }
    }
    
    func amountAdded(session: Session, exercise: Exercise) -> Int {
        return (addingExercises.filter { $0.id == exercise.id }.count) +
        (session.sessionExercises.filter { $0.exercise.id == exercise.id}.count)
        
    /*
        var count=0
        for ex in session.sessionExercises where ex.exercise.id == exercise.id {
            count += 1
        }
        return count*/
    }
    
    func showingMinusIcon(session: Session, id: UUID) -> Bool{
        return (isInAdding(id: id) || (!isInRemoving(id: id) && isInSession(session: session, id: id)))
    }
    
    func isInRemoving(id: UUID) -> Bool {
        return removingExercises.contains(where: { $0.id == id})
    }
    
    func isInAdding(id: UUID) -> Bool {
        return addingExercises.contains(where: { $0.id == id})
    }
    
    func isInSession(session: Session, id: UUID) -> Bool {
        return session.sessionExercises.contains(where: { $0.exercise.id == id })
    }
    
    func endEditing() {
        addingExercises.removeAll()
        removingExercises.removeAll()
        addingExerciseSession = false
    }

    func confirmEditing(session: Session) {
        // adding exercises
        for (_, exercise) in addingExercises.enumerated() {
            addExercise(session: session, exercise: exercise)
        }
        
        // removing exercises
        for (_, sessionExercise) in removingExercises.enumerated() {
            removeExercise(session: session, sessionExercise: sessionExercise)
        }
        
        endEditing()
        withAnimation {
            renumberExercises(session: session)
        }
    }
    
    func addExercises(session: Session) {
        for (_, exercise) in addingExercises.enumerated() {
            // if it has relationship already, dont do?
            addExercise(session: session, exercise: exercise)
        }
    }
    
    func addExercise(session: Session, exercise: Exercise)  {
        // adds relations automatically
        let newSessionExercise = SessionExercise(
            order: (session.sessionExercises.last?.order ?? 0) + 1,
            session: session,
            exercise: exercise
        )
        
        modelContext.insert(newSessionExercise)
    }
    
    func removeExercise(session: Session, sessionExercise: SessionExercise) {
        print("sessoin exercise \(sessionExercise.id)")
        withAnimation {
            if let esd = session.sessionExercises.first(where: { $0.id == sessionExercise.id }) {
                modelContext.delete(esd)
                try? modelContext.save()
                self.renumberExercises(session: session)
                self.loadFeature()
            }
        }
    }
//    func removeExercise(session: Session, exercise: Exercise) {
//        withAnimation {
//            let esd = session.sessionExercises.first(where: { $0.exercise == exercise })!
//            modelContext.delete(esd)
//            try? modelContext.save()
//        }
//    }
    
    func removeExercise(session:Session, offsets: IndexSet) {
        print("ofset \(offsets)")
        
        withAnimation {
            DispatchQueue.main.async {
                for index in offsets {
                    self.modelContext.delete(session.sessionExercises[index])
                }
                
                try? self.modelContext.save()
                self.renumberExercises(session: session)
            }
        }
    }
    
    func moveExercise(session: Session, from source: IndexSet, to destination: Int) {
        var exercises = session.sessionExercises.sorted { $0.order < $1.order }
        
        exercises.move(fromOffsets: source, toOffset: destination)
        
        for (i, exercise) in exercises.enumerated() {
            exercise.order = i
        }

        try? modelContext.save()
    }
}
