//
//  SessionRepositoryProtocol.swift
//  GymTracker
//
//  Created by Codex on 2026-04-15.
//

import Foundation

protocol SessionRepositoryProtocol {
    func fetchSessions(for userId: UUID?) throws -> [Session]
    func fetchSessions(in interval: DateInterval?, for userId: UUID?) throws -> [Session]
    func createSession(userId: UUID, routine: Routine?, notes: String) throws -> Session
    func updateRoutine(for session: Session, routine: Routine?) throws
    func deleteSession(_ session: Session) throws
    func deleteSessions(_ sessions: [Session]) throws

    func renumberEntries(in session: Session) throws
    func toggleEntryCompletion(_ sessionEntry: SessionEntry) throws
    func addExercise(to session: Session, exercise: Exercise) throws -> SessionEntry
    func removeExercise(from session: Session, sessionEntry: SessionEntry) throws
    func removeExercises(from session: Session, entryIds: [UUID]) throws
    func moveExercises(in session: Session, from source: IndexSet, to destination: Int) throws
    func transferExerciseHistory(from source: Exercise, to target: Exercise, sessionIds: Set<UUID>) throws

    func addSet(to sessionEntry: SessionEntry, notes: String, isDropSet: Bool) throws -> SessionSet
    func createBlankRep(in sessionSet: SessionSet) throws -> SessionRep
    func addRep(to sessionSet: SessionSet, weight: Double, reps: Int, unit: WeightUnit) throws -> SessionRep
    func deleteRep(from sessionSet: SessionSet, rep: SessionRep) throws
    func deleteSet(from sessionEntry: SessionEntry, sessionSet: SessionSet) throws
    func duplicateSet(_ sessionSet: SessionSet) throws -> SessionSet
    func moveSet(_ sessionSet: SessionSet, to targetExercise: Exercise) throws
    func saveChanges() throws
    func toggleSetCompletion(_ sessionSet: SessionSet) throws

    func mostRecentRep(for exercise: Exercise) -> SessionRep?
    func mostRecentCardioSet(for exercise: Exercise) -> SessionSet?
}
