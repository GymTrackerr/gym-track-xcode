//
//  LocalSessionRepository.swift
//  GymTracker
//
//  Created by Codex on 2026-04-15.
//

import Foundation
import SwiftData
import SwiftUI

final class LocalSessionRepository: SessionRepositoryProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchSessions(for userId: UUID?) throws -> [Session] {
        try normalizeTimestampDoneValues()

        let descriptor: FetchDescriptor<Session>
        if let userId {
            descriptor = FetchDescriptor<Session>(
                predicate: #Predicate<Session> { session in
                    session.user_id == userId
                },
                sortBy: [SortDescriptor(\.timestamp)]
            )
        } else {
            descriptor = FetchDescriptor<Session>(sortBy: [SortDescriptor(\.timestamp)])
        }

        return try modelContext.fetch(descriptor)
    }

    func fetchSessions(in interval: DateInterval?, for userId: UUID?) throws -> [Session] {
        let sortBy = [SortDescriptor(\Session.timestamp, order: .reverse)]

        let descriptor: FetchDescriptor<Session>
        if let interval {
            let start = interval.start
            let end = interval.end

            if let userId {
                let predicate = #Predicate<Session> {
                    $0.user_id == userId && $0.timestamp >= start && $0.timestamp < end
                }
                descriptor = FetchDescriptor(predicate: predicate, sortBy: sortBy)
            } else {
                let predicate = #Predicate<Session> {
                    $0.timestamp >= start && $0.timestamp < end
                }
                descriptor = FetchDescriptor(predicate: predicate, sortBy: sortBy)
            }
        } else if let userId {
            let predicate = #Predicate<Session> {
                $0.user_id == userId
            }
            descriptor = FetchDescriptor(predicate: predicate, sortBy: sortBy)
        } else {
            descriptor = FetchDescriptor(sortBy: sortBy)
        }

        return try modelContext.fetch(descriptor)
    }

    func createSession(userId: UUID, routine: Routine?, notes: String) throws -> Session {
        let session = Session(timestamp: Date(), user_id: userId, routine: routine, notes: notes)
        modelContext.insert(session)

        if let routine {
            createSessionExercises(session: session, routine: routine)
        }

        try modelContext.save()
        return session
    }

    func updateRoutine(for session: Session, routine: Routine?) throws {
        session.routine = routine
        if let routine {
            createSessionExercises(session: session, routine: routine)
        }
        try modelContext.save()
    }

    func deleteSession(_ session: Session) throws {
        modelContext.delete(session)
        try modelContext.save()
    }

    func deleteSessions(_ sessions: [Session]) throws {
        for session in sessions {
            modelContext.delete(session)
        }
        try modelContext.save()
    }

    func renumberEntries(in session: Session) throws {
        let sortedEntries = session.sessionEntries.sorted { $0.order < $1.order }
        for (index, entry) in sortedEntries.enumerated() {
            entry.order = index
        }
        try modelContext.save()
    }

    func toggleEntryCompletion(_ sessionEntry: SessionEntry) throws {
        sessionEntry.isCompleted.toggle()
        try modelContext.save()
    }

    func addExercise(to session: Session, exercise: Exercise) throws -> SessionEntry {
        let newSessionEntry = SessionEntry(
            order: session.sessionEntries.count,
            session: session,
            exercise: exercise
        )
        modelContext.insert(newSessionEntry)
        session.sessionEntries.append(newSessionEntry)
        try modelContext.save()
        return newSessionEntry
    }

    func removeExercise(from session: Session, sessionEntry: SessionEntry) throws {
        if let persistedEntry = session.sessionEntries.first(where: { $0.id == sessionEntry.id }) {
            modelContext.delete(persistedEntry)
            session.sessionEntries.removeAll { $0.id == persistedEntry.id }
            try modelContext.save()
            try renumberEntries(in: session)
        }
    }

    func moveExercises(in session: Session, from source: IndexSet, to destination: Int) throws {
        var exercises = session.sessionEntries.sorted { $0.order < $1.order }
        exercises.move(fromOffsets: source, toOffset: destination)
        for (index, exercise) in exercises.enumerated() {
            exercise.order = index
        }
        try modelContext.save()
    }

    func transferExerciseHistory(from source: Exercise, to target: Exercise, sessionIds: Set<UUID>) throws {
        guard source.id != target.id else { return }
        guard source.type == target.type else { return }
        guard !sessionIds.isEmpty else { return }

        let sourceEntries = try modelContext.fetch(FetchDescriptor<SessionEntry>())
            .filter { $0.exercise.id == source.id }
            .filter { sessionIds.contains($0.session.id) }

        for sourceEntry in sourceEntries {
            sourceEntry.exercise = target
        }

        try modelContext.save()
    }

    func addSet(to sessionEntry: SessionEntry, notes: String, isDropSet: Bool) throws -> SessionSet {
        let newSet = SessionSet(order: sessionEntry.sets.count, sessionEntry: sessionEntry, notes: notes)
        newSet.isDropSet = isDropSet
        modelContext.insert(newSet)
        sessionEntry.sets.append(newSet)
        try modelContext.save()
        return newSet
    }

    func createBlankRep(in sessionSet: SessionSet) throws -> SessionRep {
        let newRep = SessionRep(
            sessionSet: sessionSet,
            weight: 0,
            weight_unit: .lb,
            count: 0
        )
        sessionSet.sessionReps.append(newRep)
        try modelContext.save()
        return newRep
    }

    func addRep(to sessionSet: SessionSet, weight: Double, reps: Int, unit: WeightUnit) throws -> SessionRep {
        let newRep = SessionRep(
            sessionSet: sessionSet,
            weight: weight,
            weight_unit: unit,
            count: reps
        )
        sessionSet.sessionReps.append(newRep)
        try modelContext.save()
        return newRep
    }

    func deleteRep(from sessionSet: SessionSet, rep: SessionRep) throws {
        sessionSet.sessionReps.removeAll { $0.id == rep.id }
        modelContext.delete(rep)
        if sessionSet.sessionReps.count <= 1 {
            sessionSet.isDropSet = false
        }
        try modelContext.save()
    }

    func deleteSet(from sessionEntry: SessionEntry, sessionSet: SessionSet) throws {
        sessionEntry.sets.removeAll { $0.id == sessionSet.id }
        modelContext.delete(sessionSet)
        reorderSets(sessionEntry: sessionEntry)
        try modelContext.save()
    }

    func duplicateSet(_ sessionSet: SessionSet) throws -> SessionSet {
        let sourceEntry = sessionSet.sessionEntry
        let insertionOrder = max(sessionSet.order + 1, 0)

        let duplicate = SessionSet(
            order: insertionOrder,
            sessionEntry: sourceEntry,
            notes: sessionSet.notes
        )
        duplicate.isDropSet = sessionSet.isDropSet
        duplicate.isCompleted = sessionSet.isCompleted
        duplicate.durationSeconds = sessionSet.durationSeconds
        duplicate.distance = sessionSet.distance
        duplicate.paceSeconds = sessionSet.paceSeconds
        duplicate.distanceUnit = sessionSet.distanceUnit
        duplicate.restSeconds = sessionSet.restSeconds

        for sourceRep in sessionSet.sessionReps {
            let copiedRep = SessionRep(
                sessionSet: duplicate,
                weight: sourceRep.weight,
                weight_unit: sourceRep.weightUnit,
                count: sourceRep.count,
                notes: sourceRep.notes
            )
            copiedRep.baseWeight = sourceRep.baseWeight
            copiedRep.perSideWeight = sourceRep.perSideWeight
            copiedRep.isPerSide = sourceRep.isPerSide
            duplicate.sessionReps.append(copiedRep)
        }

        for set in sourceEntry.sets where set.order >= insertionOrder {
            set.order += 1
        }
        modelContext.insert(duplicate)
        sourceEntry.sets.append(duplicate)
        reorderSets(sessionEntry: sourceEntry)
        try modelContext.save()
        return duplicate
    }

    func moveSet(_ sessionSet: SessionSet, to targetExercise: Exercise) throws {
        let sourceEntry = sessionSet.sessionEntry
        let session = sourceEntry.session
        guard sourceEntry.exercise.id != targetExercise.id else { return }

        let targetEntry = SessionEntryResolver.ensureSessionEntry(
            for: targetExercise,
            in: session,
            context: modelContext
        )

        sourceEntry.sets.removeAll { $0.id == sessionSet.id }
        sessionSet.sessionEntry = targetEntry
        sessionSet.order = targetEntry.sets.count
        targetEntry.sets.append(sessionSet)

        reorderSets(sessionEntry: sourceEntry)
        if sourceEntry.id != targetEntry.id {
            reorderSets(sessionEntry: targetEntry)
        }

        try modelContext.save()
    }

    func saveChanges() throws {
        try modelContext.save()
    }

    func toggleSetCompletion(_ sessionSet: SessionSet) throws {
        sessionSet.isCompleted.toggle()
        try modelContext.save()
    }

    func mostRecentRep(for exercise: Exercise) -> SessionRep? {
        for entry in recentEntries(for: exercise) {
            let sortedSets = entry.sets.sorted { $0.timestamp > $1.timestamp }
            for sessionSet in sortedSets {
                for rep in sessionSet.sessionReps.reversed() {
                    if rep.weight > 0 || rep.count > 0 {
                        return rep
                    }
                }
            }
        }
        return nil
    }

    func mostRecentCardioSet(for exercise: Exercise) -> SessionSet? {
        for entry in recentEntries(for: exercise) {
            let sortedSets = entry.sets.sorted { $0.timestamp > $1.timestamp }
            for sessionSet in sortedSets where isMeaningfulCardioSet(sessionSet) {
                return sessionSet
            }
        }
        return nil
    }

    private func createSessionExercises(session: Session, routine: Routine) {
        for exerciseSplit in routine.exerciseSplits {
            let newSessionEntry = SessionEntry(
                session: session,
                exerciseSplitDay: exerciseSplit
            )
            modelContext.insert(newSessionEntry)
            session.sessionEntries.append(newSessionEntry)
        }
    }

    private func reorderSets(sessionEntry: SessionEntry) {
        let sortedSets = sessionEntry.sets.sorted { $0.order < $1.order }
        for (index, set) in sortedSets.enumerated() {
            set.order = index
        }
    }

    private func recentEntries(for exercise: Exercise) -> [SessionEntry] {
        let descriptor = FetchDescriptor<SessionEntry>()
        let allEntries = (try? modelContext.fetch(descriptor)) ?? []
        return allEntries
            .filter { $0.exercise.id == exercise.id }
            .sorted { $0.session.timestamp > $1.session.timestamp }
    }

    private func isMeaningfulCardioSet(_ sessionSet: SessionSet) -> Bool {
        let hasDuration = (sessionSet.durationSeconds ?? 0) > 0
        let hasDistance = (sessionSet.distance ?? 0) > 0
        let hasPace = (sessionSet.paceSeconds ?? 0) > 0
        return hasDuration || hasDistance || hasPace
    }

    private func normalizeTimestampDoneValues() throws {
        var didChange = false
        for session in try modelContext.fetch(FetchDescriptor<Session>()) {
            if session.timestampDone == .distantPast || session.timestampDone == Date(timeIntervalSince1970: 0) {
                session.timestampDone = session.timestamp
                didChange = true
            }
        }

        if didChange {
            try modelContext.save()
        }
    }
}
