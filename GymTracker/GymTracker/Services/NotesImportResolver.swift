import Foundation
import SwiftData

struct ResolutionResult {
    var resolvedRoutine: Routine?
    var resolvedExercises: [String: Exercise]
    var unresolvedExercises: [String]
    var createdRoutineId: UUID? = nil
}

struct ExerciseResolution {
    var resolved: Exercise?
    var candidates: [Exercise]
}

final class NotesImportResolver {
    func resolve(
        draft: NotesImportDraft,
        userId: UUID,
        context: ModelContext
    ) throws -> ResolutionResult {
#if DEBUG
        print("[NotesImportResolver] resolve called for user \(userId)")
#endif
        let routine = try resolveRoutine(
            routineNameRaw: draft.routineNameRaw,
            userId: userId,
            context: context
        )

        let rawExerciseNames = rawExerciseNames(from: draft)
        let exerciseMap = try resolveExercises(
            rawNames: rawExerciseNames,
            userId: userId,
            context: context
        )

        var resolvedExercises: [String: Exercise] = [:]
        var unresolvedExercises: [String] = []

        for rawName in rawExerciseNames {
            if let resolution = exerciseMap[rawName], let resolved = resolution.resolved {
                resolvedExercises[rawName] = resolved
            } else {
                unresolvedExercises.append(rawName)
            }
        }

        return ResolutionResult(
            resolvedRoutine: routine,
            resolvedExercises: resolvedExercises,
            unresolvedExercises: unresolvedExercises
        )
    }

    func resolveRoutine(
        routineNameRaw: String?,
        userId: UUID,
        context: ModelContext
    ) throws -> Routine? {
#if DEBUG
        print("[NotesImportResolver] resolveRoutine called with routineNameRaw=\(routineNameRaw ?? "nil")")
#endif
        guard let routineNameRaw else { return nil }
        let normalizedTarget = normalize(routineNameRaw)
        guard !normalizedTarget.isEmpty else { return nil }

        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate<Routine> { routine in
                routine.user_id == userId && routine.isArchived == false
            },
            sortBy: [SortDescriptor(\.name)]
        )

        let routines = try context.fetch(descriptor)
        return routines.first { routine in
            if normalize(routine.name) == normalizedTarget {
                return true
            }

            return routine.aliases.contains { alias in
                normalize(alias) == normalizedTarget
            }
        }
    }

    func resolveExercises(
        rawNames: [String],
        userId: UUID,
        context: ModelContext
    ) throws -> [String: ExerciseResolution] {
#if DEBUG
        print("[NotesImportResolver] resolveExercises called for \(rawNames.count) raw names")
#endif
        let targets = deduplicatedNonEmpty(rawNames)
        guard !targets.isEmpty else { return [:] }

        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { exercise in
                exercise.user_id == userId && exercise.isArchived == false
            },
            sortBy: [SortDescriptor(\.name)]
        )

        let exercises = try context.fetch(descriptor)
        var result: [String: ExerciseResolution] = [:]

        for rawName in targets {
            let normalizedTarget = normalize(rawName)
            let candidates = exercises.filter { exercise in
                if normalize(exercise.name) == normalizedTarget {
                    return true
                }

                let aliases = exercise.aliases ?? []
                return aliases.contains { alias in
                    normalize(alias) == normalizedTarget
                }
            }

            result[rawName] = ExerciseResolution(
                resolved: candidates.first,
                candidates: candidates
            )
        }

        return result
    }

    @discardableResult
    func addRoutineAliasIfNeeded(
        routine: Routine,
        aliasRaw: String,
        rememberAlias: Bool
    ) -> Bool {
#if DEBUG
        print("[NotesImportResolver] addRoutineAliasIfNeeded called for alias=\(aliasRaw), rememberAlias=\(rememberAlias)")
#endif
        guard rememberAlias else { return false }

        let normalizedAlias = normalize(aliasRaw)
        guard !normalizedAlias.isEmpty else { return false }

        if normalize(routine.name) == normalizedAlias {
            return false
        }

        if routine.aliases.contains(where: { normalize($0) == normalizedAlias }) {
            return false
        }

        routine.aliases.append(aliasRaw.trimmingCharacters(in: .whitespacesAndNewlines))
        return true
    }

    @discardableResult
    func addExerciseAliasIfNeeded(
        exercise: Exercise,
        aliasRaw: String,
        rememberAlias: Bool
    ) -> Bool {
#if DEBUG
        print("[NotesImportResolver] addExerciseAliasIfNeeded called for exercise=\(exercise.name), alias=\(aliasRaw), rememberAlias=\(rememberAlias)")
#endif
        guard rememberAlias else { return false }

        let normalizedAlias = normalize(aliasRaw)
        guard !normalizedAlias.isEmpty else { return false }

        if normalize(exercise.name) == normalizedAlias {
            return false
        }

        var aliases = exercise.aliases ?? []
        if aliases.contains(where: { normalize($0) == normalizedAlias }) {
            return false
        }

        aliases.append(aliasRaw.trimmingCharacters(in: .whitespacesAndNewlines))
        exercise.aliases = aliases
        return true
    }
}

private extension NotesImportResolver {
    func rawExerciseNames(from draft: NotesImportDraft) -> [String] {
        var names: [String] = []

        for item in draft.items {
            switch item {
            case .strength(let strength):
                names.append(strength.exerciseNameRaw)
            case .cardio(let cardio):
                names.append(cardio.exerciseNameRaw)
            }
        }

        return deduplicatedNonEmpty(names)
    }

    func deduplicatedNonEmpty(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalize(trimmed)
            guard !key.isEmpty else { continue }
            if seen.insert(key).inserted {
                result.append(trimmed)
            }
        }

        return result
    }

    func normalize(_ input: String) -> String {
        input
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
