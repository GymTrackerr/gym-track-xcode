import Foundation
import Combine
import SwiftData

final class ProgressionEvaluationService: ServiceBase, ObservableObject {
    private let weightEpsilon = 0.0001

    func evaluateSessionIfNeeded(_ session: Session) {
        guard session.timestampDone > session.timestamp else { return }

        let sortedEntries = session.sessionEntries.sorted { $0.order < $1.order }
        for entry in sortedEntries {
            evaluateSessionEntryIfNeeded(entry)
        }

        try? modelContext.save()
    }

    private func evaluateSessionEntryIfNeeded(_ entry: SessionEntry) {
        guard let progression = entry.appliedProgression else { return }
        let exercise = entry.exercise
        guard let userId = currentUser?.id else { return }
        guard userId == entry.session.user_id else { return }

        guard let repsThreshold = repsThreshold(for: entry, progression: progression) else { return }
        guard let setsTarget = entry.appliedSetsTarget, setsTarget > 0 else { return }

        let state = resolveOrCreateState(userId: userId, exercise: exercise, progression: progression)
        if state.lastEvaluatedSessionEntryId == entry.id {
            return
        }

        let requiredSets = requiredMeaningfulSets(for: entry, setsTarget: setsTarget)
        var successfulSetResults: [(reps: Int, weight: Double)] = []
        for sessionSet in requiredSets {
            guard let setResult = evaluatedSetResult(sessionSet) else { continue }
            if setResult.reps < repsThreshold { continue }
            if let suggestedWeight = entry.suggestedWeight,
               setResult.weight + weightEpsilon < suggestedWeight {
                continue
            }
            successfulSetResults.append(setResult)
        }

        let successPolicy = progression.progressionSuccessPolicy
        let success: Bool
        switch successPolicy {
        case .allTargetsMet:
            success = requiredSets.count == setsTarget && successfulSetResults.count == setsTarget
        case .anyTopSetMet:
            success = !successfulSetResults.isEmpty
        }

        let highestSuccessfulWeight = successfulSetResults.map(\.weight).max()

        if success {
            state.successCount += 1
        } else {
            state.successCount = 0
        }

        let requiredSuccesses = max(progression.requiredSuccessSessions, 1)
        let reachedAdvanceThreshold = success && state.successCount >= requiredSuccesses

        if reachedAdvanceThreshold {
            let increment = max(progression.incrementValue, 0)
            var advanced = false

            if let currentWorkingWeight = state.workingWeight {
                state.workingWeight = currentWorkingWeight + increment
                advanced = true
            } else if let suggestedWeight = entry.suggestedWeight {
                state.workingWeight = suggestedWeight + increment
                advanced = true
            } else if let highestSuccessfulWeight {
                state.workingWeight = highestSuccessfulWeight + increment
                advanced = true
            }

            if advanced {
                state.successCount = 0
                state.lastAdvancedAt = Date()
            }
        }

        state.lastEvaluatedSessionEntryId = entry.id
    }

    private func repsThreshold(for entry: SessionEntry, progression: ProgressionProfile) -> Int? {
        switch progression.progressionType {
        case .doubleProgression:
            if let repsLow = entry.appliedRepsLow, let repsHigh = entry.appliedRepsHigh {
                return max(repsLow, repsHigh)
            }
            if let repsHigh = entry.appliedRepsHigh { return repsHigh }
            if let repsLow = entry.appliedRepsLow { return repsLow }
            return entry.appliedRepsTarget
        case .linear, .custom:
            // Custom currently uses the same threshold semantics as linear in v1.
            if let repsTarget = entry.appliedRepsTarget { return repsTarget }
            if let repsLow = entry.appliedRepsLow, let repsHigh = entry.appliedRepsHigh {
                return max(repsLow, repsHigh)
            }
            if let repsHigh = entry.appliedRepsHigh { return repsHigh }
            if let repsLow = entry.appliedRepsLow { return repsLow }
            return nil
        }
    }

    private func requiredMeaningfulSets(for entry: SessionEntry, setsTarget: Int) -> [SessionSet] {
        let exerciseKind = entry.exercise.setDisplayKind
        return entry.sets
            .sorted { $0.order < $1.order }
            .filter { SetDisplayFormatter.isMeaningfulSet($0, exerciseKind: exerciseKind) }
            .prefix(setsTarget)
            .map { $0 }
    }

    private func evaluatedSetResult(_ sessionSet: SessionSet) -> (reps: Int, weight: Double)? {
        let reps = sessionSet.sessionReps
            .filter { $0.count > 0 || $0.weight > 0 }
            .sorted { $0.id.uuidString < $1.id.uuidString }

        guard let primaryRep = reps.first else { return nil }
        return (primaryRep.count, primaryRep.weight)
    }

    private func resolveOrCreateState(
        userId: UUID,
        exercise: Exercise,
        progression: ProgressionProfile
    ) -> ProgressionState {
        let exerciseId = exercise.id
        let progressionId = progression.id

        let descriptor = FetchDescriptor<ProgressionState>(
            predicate: #Predicate<ProgressionState> { state in
                state.user_id == userId
                && state.exercise?.id == exerciseId
                && state.progression?.id == progressionId
            }
        )

        let matches = (try? modelContext.fetch(descriptor)) ?? []
        if let first = matches.sorted(by: { $0.id.uuidString < $1.id.uuidString }).first {
            return first
        }

        let history = historicalEntries(userId: userId, exerciseId: exercise.id)
        let matchingProgressionHistory = history.filter { $0.appliedProgression?.id == progression.id }

        let created = ProgressionState(
            user_id: userId,
            exercise: exercise,
            progression: progression,
            workingWeight: backfilledWorkingWeight(
                history: history,
                matchingProgressionHistory: matchingProgressionHistory,
                exerciseKind: exercise.setDisplayKind
            ),
            successCount: backfilledSuccessCount(
                matchingProgressionHistory: matchingProgressionHistory,
                progression: progression
            ),
            lastEvaluatedSessionEntryId: nil,
            lastAdvancedAt: nil
        )
        modelContext.insert(created)
        return created
    }

    private func backfilledWorkingWeight(
        history: [SessionEntry],
        matchingProgressionHistory: [SessionEntry],
        exerciseKind: SetDisplayExerciseKind
    ) -> Double? {
        let preferredHistory = matchingProgressionHistory.isEmpty ? history : matchingProgressionHistory

        for entry in preferredHistory {
            let sortedSets = entry.sets.sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp { return lhs.timestamp > rhs.timestamp }
                return lhs.order > rhs.order
            }
            for sessionSet in sortedSets {
                guard SetDisplayFormatter.isMeaningfulSet(sessionSet, exerciseKind: exerciseKind) else { continue }
                if let rep = sessionSet.sessionReps.reversed().first(where: { $0.weight > 0 }) {
                    return rep.weight
                }
            }
        }
        return nil
    }

    private func backfilledSuccessCount(
        matchingProgressionHistory: [SessionEntry],
        progression: ProgressionProfile
    ) -> Int {
        guard !matchingProgressionHistory.isEmpty else { return 0 }
        let requiredSuccesses = max(progression.requiredSuccessSessions, 1)
        guard requiredSuccesses > 1 else { return 0 }

        var streak = 0
        for entry in matchingProgressionHistory {
            guard let isSuccess = highConfidenceSuccess(for: entry, progression: progression) else { break }
            if isSuccess {
                streak += 1
                if streak >= requiredSuccesses {
                    return requiredSuccesses - 1
                }
            } else {
                break
            }
        }

        if streak > 0 {
            return min(streak, requiredSuccesses - 1)
        }
        return 0
    }

    private func highConfidenceSuccess(for entry: SessionEntry, progression: ProgressionProfile) -> Bool? {
        guard let setsTarget = entry.appliedSetsTarget, setsTarget > 0 else { return nil }
        guard let repsThreshold = repsThreshold(for: entry, progression: progression) else { return nil }

        let requiredSets = requiredMeaningfulSets(for: entry, setsTarget: setsTarget)
        let successfulSetCount = requiredSets.reduce(into: 0) { partialResult, sessionSet in
            guard let setResult = evaluatedSetResult(sessionSet) else { return }
            if setResult.reps >= repsThreshold {
                partialResult += 1
            }
        }

        switch progression.progressionSuccessPolicy {
        case .allTargetsMet:
            return requiredSets.count == setsTarget && successfulSetCount == setsTarget
        case .anyTopSetMet:
            return successfulSetCount > 0
        }
    }

    private func historicalEntries(userId: UUID, exerciseId: UUID) -> [SessionEntry] {
        let descriptor = FetchDescriptor<SessionEntry>(
            predicate: #Predicate<SessionEntry> { entry in
                entry.session.user_id == userId
                && entry.exercise.id == exerciseId
                && entry.session.timestampDone > entry.session.timestamp
            },
            sortBy: [SortDescriptor(\.session.timestamp, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
