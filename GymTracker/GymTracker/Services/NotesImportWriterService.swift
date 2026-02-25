import Foundation
import SwiftData

enum NotesImportWriterError: LocalizedError {
    case missingDate
    case missingTimeRange
    case unresolvedExercises([String])

    var errorDescription: String? {
        switch self {
        case .missingDate:
            return "Cannot import session without a date."
        case .missingTimeRange:
            return "Cannot import session without a resolved time range."
        case .unresolvedExercises(let names):
            return "Cannot import unresolved exercises: \(names.joined(separator: ", "))."
        }
    }
}

final class NotesImportWriterService {
    func duplicateExists(
        draft: NotesImportDraft,
        userId: UUID,
        context: ModelContext
    ) throws -> Bool {
#if DEBUG
        print("[NotesImportWriterService] duplicateExists called for user \(userId), hash=\(draft.importHash)")
#endif
        let importHash = draft.importHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !importHash.isEmpty else { return false }

        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate<Session> { session in
                session.user_id == userId && session.importHash == importHash
            }
        )

        let exists = try !context.fetch(descriptor).isEmpty
#if DEBUG
        print("[NotesImportWriterService] duplicateExists result=\(exists)")
#endif
        return exists
    }

    func commit(
        draft: NotesImportDraft,
        resolution: ResolutionResult,
        userId: UUID,
        context: ModelContext,
        defaultWeightUnit: WeightUnit
    ) throws -> Session {
#if DEBUG
        print("[NotesImportWriterService] commit called for user \(userId), items=\(draft.items.count), hash=\(draft.importHash)")
#endif
        guard draft.parsedDate != nil else {
            throw NotesImportWriterError.missingDate
        }
        guard draft.startTime != nil, draft.endTime != nil else {
            throw NotesImportWriterError.missingTimeRange
        }

        let unresolved = unresolvedExerciseNames(in: draft, resolution: resolution)
        if !unresolved.isEmpty {
            throw NotesImportWriterError.unresolvedExercises(unresolved)
        }

        let timestampResult = resolveTimestamps(for: draft)
        let sessionNotes = buildSessionNotes(
            draft: draft,
            additionalWarnings: timestampResult.warnings
        )

        let session = Session(
            timestamp: timestampResult.start,
            user_id: userId,
            routine: resolution.resolvedRoutine,
            notes: sessionNotes
        )
        session.timestampDone = timestampResult.end
        session.importHash = draft.importHash

        context.insert(session)

        do {
            var entryOrder = 0
            for item in draft.items {
                switch item {
                case .strength(let strength):
                    let exercise = try resolvedExercise(
                        rawName: strength.exerciseNameRaw,
                        resolution: resolution
                    )

                    let entry = SessionEntry(order: entryOrder, session: session, exercise: exercise)
                    context.insert(entry)
                    session.sessionEntries.append(entry)

                    for (setIndex, parsedSet) in strength.sets.enumerated() {
                        let set = SessionSet(order: setIndex, sessionEntry: entry, notes: strength.notes)
                        set.isCompleted = true
                        set.restSeconds = parsedSet.restSeconds

                        context.insert(set)
                        entry.sets.append(set)

                        let repWeight = parsedSet.weight ?? 0
                        let repWeightUnit = parsedSet.weight == nil ? defaultWeightUnit : parsedSet.weightUnit
                        let repNote = parsedSet.weight == nil
                            ? "Imported: weight not specified (treated as 0)."
                            : nil

                        let rep = SessionRep(
                            sessionSet: set,
                            weight: repWeight,
                            weight_unit: repWeightUnit,
                            count: parsedSet.reps,
                            notes: repNote
                        )

                        rep.baseWeight = parsedSet.baseWeight
                        rep.perSideWeight = parsedSet.perSideWeight
                        rep.isPerSide = parsedSet.isPerSide

                        context.insert(rep)
                        set.sessionReps.append(rep)
                    }
                    entry.isCompleted = !entry.sets.isEmpty && entry.sets.allSatisfy(\.isCompleted)

                    entryOrder += 1

                case .cardio(let cardio):
                    let exercise = try resolvedExercise(
                        rawName: cardio.exerciseNameRaw,
                        resolution: resolution
                    )

                    let entry = SessionEntry(order: entryOrder, session: session, exercise: exercise)
                    context.insert(entry)
                    session.sessionEntries.append(entry)

                    for (setIndex, parsedSet) in cardio.sets.enumerated() {
                        let set = SessionSet(order: setIndex, sessionEntry: entry, notes: cardio.notes)
                        set.isCompleted = true
                        set.durationSeconds = parsedSet.durationSeconds
                        set.distance = parsedSet.distance
                        set.distanceUnit = parsedSet.distanceUnit
                        set.paceSeconds = parsedSet.paceSeconds

                        context.insert(set)
                        entry.sets.append(set)
                    }
                    entry.isCompleted = !entry.sets.isEmpty && entry.sets.allSatisfy(\.isCompleted)

                    entryOrder += 1
                }
            }

            if let routine = resolution.resolvedRoutine,
               resolution.createdRoutineId == routine.id {
                populateRoutineTemplateIfNeeded(
                    routine: routine,
                    draft: draft,
                    resolution: resolution,
                    context: context
                )
            }

            try context.save()
#if DEBUG
            print("[NotesImportWriterService] commit save succeeded")
#endif
            return session
        } catch {
#if DEBUG
            print("[NotesImportWriterService] commit failed, rolling back: \(error)")
#endif
            context.rollback()
            throw error
        }
    }
}

private extension NotesImportWriterService {
    func unresolvedExerciseNames(
        in draft: NotesImportDraft,
        resolution: ResolutionResult
    ) -> [String] {
        var missing: [String] = []

        for item in draft.items {
            let rawName: String
            switch item {
            case .strength(let strength):
                rawName = strength.exerciseNameRaw
            case .cardio(let cardio):
                rawName = cardio.exerciseNameRaw
            }

            let key = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            if resolution.resolvedExercises[key] == nil {
                missing.append(key)
            }
        }

        return deduplicatePreservingOrder(missing)
    }

    func resolvedExercise(
        rawName: String,
        resolution: ResolutionResult
    ) throws -> Exercise {
        let key = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exercise = resolution.resolvedExercises[key] {
            return exercise
        }
        throw NotesImportWriterError.unresolvedExercises([key])
    }

    func resolveTimestamps(for draft: NotesImportDraft) -> (start: Date, end: Date, warnings: [String]) {
        let start = draft.startTime ?? draft.parsedDate ?? Date()
        let end = draft.endTime ?? start
        return (start, end, [])
    }

    func buildSessionNotes(
        draft: NotesImportDraft,
        additionalWarnings: [String]
    ) -> String {
        var sections: [String] = []

        let allWarnings = draft.warnings + additionalWarnings
        if !allWarnings.isEmpty {
            let text = allWarnings.map { "- \($0)" }.joined(separator: "\n")
            sections.append("Import warnings:\n\(text)")
        }

        if !draft.unknownLines.isEmpty {
            let text = draft.unknownLines.map { "- \($0)" }.joined(separator: "\n")
            sections.append("Unparsed lines:\n\(text)")
        }

        return sections.joined(separator: "\n\n")
    }

    func deduplicatePreservingOrder(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for value in values {
            if seen.insert(value).inserted {
                result.append(value)
            }
        }

        return result
    }

    func populateRoutineTemplateIfNeeded(
        routine: Routine,
        draft: NotesImportDraft,
        resolution: ResolutionResult,
        context: ModelContext
    ) {
        var exerciseOrder = routine.exerciseSplits.count
        var seenExerciseIds = Set(routine.exerciseSplits.map(\.exercise.id))

        for rawName in rawExerciseNamesInDraftOrder(from: draft) {
            let key = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let exercise = resolution.resolvedExercises[key] else { continue }
            if seenExerciseIds.contains(exercise.id) { continue }

            let split = ExerciseSplitDay(order: exerciseOrder, routine: routine, exercise: exercise)
            context.insert(split)
            routine.exerciseSplits.append(split)
            seenExerciseIds.insert(exercise.id)
            exerciseOrder += 1
        }
    }

    func rawExerciseNamesInDraftOrder(from draft: NotesImportDraft) -> [String] {
        var names: [String] = []
        var seen: Set<String> = []

        for item in draft.items {
            let rawName: String
            switch item {
            case .strength(let strength):
                rawName = strength.exerciseNameRaw
            case .cardio(let cardio):
                rawName = cardio.exerciseNameRaw
            }

            let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                names.append(trimmed)
            }
        }

        return names
    }

}
