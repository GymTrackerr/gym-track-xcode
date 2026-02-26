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
    @Published var removingExercises: [SessionEntry] = []
    
    func renumberExercises(session: Session) {
        let exercises = session.sessionEntries.sorted { $0.order < $1.order }
        
        for (i, exercise) in exercises.enumerated() {
            print("number \(i)")
            exercise.order = i
        }
        
        try? modelContext.save()
    }

    func toggleCompletion(sessionEntry: SessionEntry) {
        withAnimation {
            sessionEntry.isCompleted.toggle()
            try? modelContext.save()
        }
    }
    
    func amountAdded(session: Session, exercise: Exercise) -> Int {
        return (addingExercises.filter { $0.id == exercise.id }.count) +
        (session.sessionEntries.filter { $0.exercise.id == exercise.id}.count)
        
    /*
        var count=0
        for ex in session.sessionEntries where ex.exercise.id == exercise.id {
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
        return session.sessionEntries.contains(where: { $0.exercise.id == id })
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
        for (_, sessionEntry) in removingExercises.enumerated() {
            removeExercise(session: session, sessionEntry: sessionEntry)
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
        let newSessionEntry = SessionEntry(
            order: session.sessionEntries.count,
            session: session,
            exercise: exercise
        )
        
        withAnimation {
            modelContext.insert(newSessionEntry)
            session.sessionEntries.append(newSessionEntry)
            try? modelContext.save()
        }
    }
    
    func removeExercise(session: Session, sessionEntry: SessionEntry) {
        print("session exercise \(sessionEntry.id)")
        withAnimation {
            if let esd = session.sessionEntries.first(where: { $0.id == sessionEntry.id }) {
                // TODO: crashed here, EXC_BAD_ACESS
                // this was     half solved by nullifying relationships in SessionEntry model
                modelContext.delete(esd)
                session.sessionEntries.removeAll { $0.id == esd.id }
                try? modelContext.save()
                self.renumberExercises(session: session)
                self.loadFeature()
            }
        }
    }
    
    func removeExercise(session:Session, offsets: IndexSet) {
        print("ofset \(offsets)")
        
        withAnimation {
            DispatchQueue.main.async {
                let sortedEntries = session.sessionEntries.sorted { $0.order < $1.order }
                for index in offsets {
                    guard sortedEntries.indices.contains(index) else { continue }
                    let entry = sortedEntries[index]
                    self.modelContext.delete(entry)
                    session.sessionEntries.removeAll { $0.id == entry.id }
                }
                
                try? self.modelContext.save()
                self.renumberExercises(session: session)
            }
        }
    }

    func transferExerciseHistory(from source: Exercise, to target: Exercise, sessionIds: Set<UUID>) throws {
        guard source.id != target.id else { return }
        guard source.type == target.type else { return }
        guard !sessionIds.isEmpty else { return }

        let sourceEntries = try modelContext.fetch(FetchDescriptor<SessionEntry>())
            .filter { $0.exercise.id == source.id }
            .filter { sessionIds.contains($0.session.id) }

        guard !sourceEntries.isEmpty else { return }

        for sourceEntry in sourceEntries {
            // Just update the exercise reference - preserves isCompleted and all other state
            sourceEntry.exercise = target
        }

        try modelContext.save()
    }
    
    func moveExercise(session: Session, from source: IndexSet, to destination: Int) {
        var exercises = session.sessionEntries.sorted { $0.order < $1.order }
        
        exercises.move(fromOffsets: source, toOffset: destination)
        
        for (i, exercise) in exercises.enumerated() {
            exercise.order = i
        }

        try? modelContext.save()
    }
}
