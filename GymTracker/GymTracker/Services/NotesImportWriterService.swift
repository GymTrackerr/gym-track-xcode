import Foundation
import SwiftData

enum NotesImportWriterError: LocalizedError {
    case missingDate
    case unresolvedExercises([String])

    var errorDescription: String? {
        switch self {
        case .missingDate:
            return "Cannot import session without a date."
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
                        set.durationSeconds = parsedSet.durationSeconds
                        set.distance = parsedSet.distance
                        set.distanceUnit = parsedSet.distanceUnit
                        set.paceSeconds = parsedSet.paceSeconds

                        context.insert(set)
                        entry.sets.append(set)
                    }

                    entryOrder += 1
                }
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
        let calendar = Calendar.current

        guard let parsedDate = draft.parsedDate else {
            return (Date(), Date(), [])
        }

        let start: Date
        if let providedStart = draft.startTime {
            start = providedStart
        } else {
            var components = calendar.dateComponents(in: TimeZone.current, from: parsedDate)
            components.hour = 12
            components.minute = 0
            components.second = 0
            start = calendar.date(from: components) ?? parsedDate
        }

        if let providedEnd = draft.endTime {
            return (start, providedEnd, [])
        }

        let fallbackEnd = calendar.date(byAdding: .minute, value: 60, to: start) ?? start
        return (start, fallbackEnd, ["Missing end time; estimated end time used."])
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
}
