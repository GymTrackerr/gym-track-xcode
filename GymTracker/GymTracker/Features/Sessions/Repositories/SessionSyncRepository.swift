//
//  SessionSyncRepository.swift
//  GymTracker
//
//  Created by Codex on 2026-04-16.
//

import Foundation

final class SessionSyncRepository: BaseSyncRepository, SessionRepositoryProtocol {
    private let localRepository: SessionRepositoryProtocol

    init(
        localRepository: SessionRepositoryProtocol,
        queueStore: SyncQueueStore,
        eligibilityService: SyncEligibilityService
    ) {
        self.localRepository = localRepository
        super.init(queueStore: queueStore, eligibilityService: eligibilityService)
    }

    func fetchSessions(for userId: UUID?) throws -> [Session] { try localRepository.fetchSessions(for: userId) }
    func fetchSessions(in interval: DateInterval?, for userId: UUID?) throws -> [Session] { try localRepository.fetchSessions(in: interval, for: userId) }

    func createSession(userId: UUID, routine: Routine?, notes: String) throws -> Session {
        let session = try localRepository.createSession(userId: userId, routine: routine, notes: notes)
        enqueue(for: session, operation: .create)
        return session
    }

    func createProgramSession(
        userId: UUID,
        program: Program,
        programBlock: ProgramBlock,
        programWorkout: ProgramWorkout,
        notes: String,
        programWeekIndex: Int?,
        programSplitIndex: Int?
    ) throws -> Session {
        let session = try localRepository.createProgramSession(
            userId: userId,
            program: program,
            programBlock: programBlock,
            programWorkout: programWorkout,
            notes: notes,
            programWeekIndex: programWeekIndex,
            programSplitIndex: programSplitIndex
        )
        enqueue(for: session, operation: .create)
        return session
    }

    func updateRoutine(for session: Session, routine: Routine?) throws {
        try localRepository.updateRoutine(for: session, routine: routine)
        enqueue(for: session, operation: .update)
    }

    func deleteSession(_ session: Session) throws {
        try localRepository.deleteSession(session)
        enqueue(for: session, operation: .softDelete)
    }

    func deleteSessions(_ sessions: [Session]) throws {
        try localRepository.deleteSessions(sessions)
        for session in sessions {
            enqueue(for: session, operation: .softDelete)
        }
    }

    func renumberEntries(in session: Session) throws { try localRepository.renumberEntries(in: session); enqueue(for: session, operation: .update) }
    func toggleEntryCompletion(_ sessionEntry: SessionEntry) throws { try localRepository.toggleEntryCompletion(sessionEntry); enqueue(for: sessionEntry.session, operation: .update) }

    func addExercise(to session: Session, exercise: Exercise) throws -> SessionEntry {
        let entry = try localRepository.addExercise(to: session, exercise: exercise)
        enqueue(for: session, operation: .update)
        return entry
    }

    func removeExercise(from session: Session, sessionEntry: SessionEntry) throws { try localRepository.removeExercise(from: session, sessionEntry: sessionEntry); enqueue(for: session, operation: .update) }
    func removeExercises(from session: Session, entryIds: [UUID]) throws { try localRepository.removeExercises(from: session, entryIds: entryIds); enqueue(for: session, operation: .update) }
    func moveExercises(in session: Session, from source: IndexSet, to destination: Int) throws { try localRepository.moveExercises(in: session, from: source, to: destination); enqueue(for: session, operation: .update) }
    func transferExerciseHistory(from source: Exercise, to target: Exercise, sessionIds: Set<UUID>) throws {
        let sessions = try localRepository.fetchSessions(for: nil).filter { sessionIds.contains($0.id) }
        try localRepository.transferExerciseHistory(from: source, to: target, sessionIds: sessionIds)
        for session in sessions { enqueue(for: session, operation: .update) }
    }

    func addSet(to sessionEntry: SessionEntry, notes: String, isDropSet: Bool) throws -> SessionSet {
        let result = try localRepository.addSet(to: sessionEntry, notes: notes, isDropSet: isDropSet)
        enqueue(for: sessionEntry.session, operation: .update)
        return result
    }

    func createBlankRep(in sessionSet: SessionSet) throws -> SessionRep {
        let rep = try localRepository.createBlankRep(in: sessionSet)
        enqueue(for: sessionSet.sessionEntry.session, operation: .update)
        return rep
    }

    func addRep(to sessionSet: SessionSet, weight: Double, reps: Int, unit: WeightUnit) throws -> SessionRep {
        let rep = try localRepository.addRep(to: sessionSet, weight: weight, reps: reps, unit: unit)
        enqueue(for: sessionSet.sessionEntry.session, operation: .update)
        return rep
    }

    func deleteRep(from sessionSet: SessionSet, rep: SessionRep) throws { try localRepository.deleteRep(from: sessionSet, rep: rep); enqueue(for: sessionSet.sessionEntry.session, operation: .update) }
    func deleteSet(from sessionEntry: SessionEntry, sessionSet: SessionSet) throws { try localRepository.deleteSet(from: sessionEntry, sessionSet: sessionSet); enqueue(for: sessionEntry.session, operation: .update) }

    func duplicateSet(_ sessionSet: SessionSet) throws -> SessionSet {
        let value = try localRepository.duplicateSet(sessionSet)
        enqueue(for: sessionSet.sessionEntry.session, operation: .update)
        return value
    }

    func moveSet(_ sessionSet: SessionSet, to targetExercise: Exercise) throws {
        try localRepository.moveSet(sessionSet, to: targetExercise)
        enqueue(for: sessionSet.sessionEntry.session, operation: .update)
    }

    func saveChanges(for session: Session) throws { try localRepository.saveChanges(for: session); enqueue(for: session, operation: .update) }
    func toggleSetCompletion(_ sessionSet: SessionSet) throws { try localRepository.toggleSetCompletion(sessionSet); enqueue(for: sessionSet.sessionEntry.session, operation: .update) }

    func mostRecentRep(for exercise: Exercise) -> SessionRep? { localRepository.mostRecentRep(for: exercise) }
    func mostRecentCardioSet(for exercise: Exercise) -> SessionSet? { localRepository.mostRecentCardioSet(for: exercise) }

    private func enqueue(for session: Session, operation: SyncQueueOperation) {
        enqueueRootMutationIfNeeded(root: session, operation: operation)
    }
}
