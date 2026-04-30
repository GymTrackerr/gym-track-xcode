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
    private let repository: SessionRepositoryProtocol
    var progressionService: ProgressionService?

    init(context: ModelContext, repository: SessionRepositoryProtocol? = nil) {
        self.repository = repository ?? LocalSessionRepository(modelContext: context)
        super.init(context: context)
    }
    
    func renumberExercises(session: Session) {
        try? repository.renumberEntries(in: session)
    }

    func toggleCompletion(sessionEntry: SessionEntry) {
        withAnimation {
            try? repository.toggleEntryCompletion(sessionEntry)
        }
    }
    
    func amountAdded(session: Session, exercise: Exercise) -> Int {
        return (addingExercises.filter { $0.id == exercise.id }.count) +
        (session.sessionEntries.filter { $0.exercise.id == exercise.id}.count)
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
    
    @discardableResult
    func addExercise(session: Session, exercise: Exercise) -> SessionEntry? {
        var sessionEntry: SessionEntry?
        withAnimation {
            sessionEntry = try? repository.addExercise(to: session, exercise: exercise)
            if let sessionEntry {
                let didMutate = progressionService?.applySnapshot(to: sessionEntry) ?? false
                if didMutate {
                    try? repository.saveChanges(for: session)
                }
            }
        }
        return sessionEntry
    }
    
    func removeExercise(session: Session, sessionEntry: SessionEntry) {
        print("session exercise \(sessionEntry.id)")
        withAnimation {
            try? repository.removeExercise(from: session, sessionEntry: sessionEntry)
            self.loadFeature()
        }
    }
    
    func removeExercise(session:Session, offsets: IndexSet) {
        print("ofset \(offsets)")

        let sortedEntries = session.sessionEntries.sorted { $0.order < $1.order }
        let entryIds: [UUID] = offsets.compactMap { (index: Int) -> UUID? in
            guard sortedEntries.indices.contains(index) else { return nil }
            return sortedEntries[index].id
        }
        guard !entryIds.isEmpty else { return }

        withAnimation {
            try? repository.removeExercises(from: session, entryIds: entryIds)
        }
    }

    func transferExerciseHistory(from source: Exercise, to target: Exercise, sessionIds: Set<UUID>) throws {
        try repository.transferExerciseHistory(from: source, to: target, sessionIds: sessionIds)
    }
    
    func moveExercise(session: Session, from source: IndexSet, to destination: Int) {
        try? repository.moveExercises(in: session, from: source, to: destination)
    }
}
