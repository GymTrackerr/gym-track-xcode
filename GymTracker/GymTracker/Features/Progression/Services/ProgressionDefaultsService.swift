import Foundation
import SwiftData
import Combine

final class ProgressionDefaultsService: ServiceBase, ObservableObject {
    private let setService: SetService

    init(context: ModelContext, setService: SetService) {
        self.setService = setService
        super.init(context: context)
    }

    func applyDefaultsIfAvailable(to entry: SessionEntry) -> Bool {
        guard let userId = currentUser?.id else { return false }
        guard entry.session.user_id == userId else { return false }

        let exerciseDefault = fetchExerciseDefault(userId: userId, exerciseId: entry.exercise.id)
        let userDefault = fetchUserDefault(userId: userId)
        let resolvedSetsTarget: Int?
        let resolvedRepsTarget: Int?
        let resolvedRepsLow: Int?
        let resolvedRepsHigh: Int?
        let resolvedProgression: ProgressionProfile?
        if let exerciseDefault {
            resolvedSetsTarget = exerciseDefault.setsTarget
            resolvedRepsTarget = exerciseDefault.repsTarget
            resolvedRepsLow = exerciseDefault.repsLow
            resolvedRepsHigh = exerciseDefault.repsHigh
            resolvedProgression = exerciseDefault.progression
        } else {
            resolvedSetsTarget = userDefault?.setsTarget
            resolvedRepsTarget = userDefault?.repsTarget
            resolvedRepsLow = userDefault?.repsLow
            resolvedRepsHigh = userDefault?.repsHigh
            resolvedProgression = userDefault?.progression
        }

        let hasUsefulDefaults = resolvedSetsTarget != nil
            || resolvedRepsTarget != nil
            || resolvedRepsLow != nil
            || resolvedRepsHigh != nil
            || resolvedProgression != nil

        guard hasUsefulDefaults else { return false }

        entry.appliedSetsTarget = resolvedSetsTarget
        entry.appliedRepsTarget = resolvedRepsTarget
        entry.appliedRepsLow = resolvedRepsLow
        entry.appliedRepsHigh = resolvedRepsHigh
        entry.appliedProgression = resolvedProgression
        entry.appliedProgressionNameSnapshot = resolvedProgression?.name
        entry.suggestedWeight = resolveSuggestedWeight(
            userId: userId,
            exercise: entry.exercise,
            progression: resolvedProgression
        )
        return true
    }

    func mergeProgramOverride(_ overrideModel: ProgramDayExerciseOverride, into entry: SessionEntry) {
        if let setsTarget = overrideModel.setsTarget {
            entry.appliedSetsTarget = setsTarget
        }
        if let repsTarget = overrideModel.repsTarget {
            entry.appliedRepsTarget = repsTarget
        }
        if let repsLow = overrideModel.repsLow {
            entry.appliedRepsLow = repsLow
        }
        if let repsHigh = overrideModel.repsHigh {
            entry.appliedRepsHigh = repsHigh
        }
        if let progression = overrideModel.progression {
            entry.appliedProgression = progression
        }

        entry.appliedProgressionNameSnapshot = entry.appliedProgression?.name
        if let userId = currentUser?.id, userId == entry.session.user_id {
            entry.suggestedWeight = resolveSuggestedWeight(
                userId: userId,
                exercise: entry.exercise,
                progression: entry.appliedProgression
            )
        }
    }

    func availableProfiles() -> [ProgressionProfile] {
        guard let userId = currentUser?.id else { return [] }
        let descriptor = FetchDescriptor<ProgressionProfile>(sortBy: [SortDescriptor(\.name)])
        let allProfiles = (try? modelContext.fetch(descriptor)) ?? []
        return allProfiles.filter { profile in
            profile.isArchived == false && (profile.user_id == nil || profile.user_id == userId)
        }
    }

    func currentUserDefault() -> UserProgressionDefault? {
        guard let userId = currentUser?.id else { return nil }
        return fetchUserDefault(userId: userId)
    }

    @discardableResult
    func upsertUserDefault(
        progression: ProgressionProfile?,
        setsTarget: Int?,
        repsTarget: Int?,
        repsLow: Int?,
        repsHigh: Int?
    ) -> Bool {
        guard let userId = currentUser?.id else { return false }
        let hasUsefulValues = progression != nil
            || setsTarget != nil
            || repsTarget != nil
            || repsLow != nil
            || repsHigh != nil

        if !hasUsefulValues {
            return removeUserDefault()
        }

        let model = fetchUserDefault(userId: userId) ?? {
            let created = UserProgressionDefault(user_id: userId)
            modelContext.insert(created)
            return created
        }()

        model.progression = progression
        model.setsTarget = setsTarget
        model.repsTarget = repsTarget
        model.repsLow = repsLow
        model.repsHigh = repsHigh
        model.timestamp = Date()
        return (try? modelContext.save()) != nil
    }

    @discardableResult
    func removeUserDefault() -> Bool {
        guard let model = currentUserDefault() else { return true }
        modelContext.delete(model)
        return (try? modelContext.save()) != nil
    }

    func currentExerciseDefault(for exercise: Exercise) -> ExerciseProgressionDefault? {
        guard let userId = currentUser?.id else { return nil }
        return fetchExerciseDefault(userId: userId, exerciseId: exercise.id)
    }

    @discardableResult
    func upsertExerciseDefault(
        for exercise: Exercise,
        progression: ProgressionProfile?,
        setsTarget: Int?,
        repsTarget: Int?,
        repsLow: Int?,
        repsHigh: Int?
    ) -> Bool {
        guard let userId = currentUser?.id else { return false }
        let hasUsefulValues = progression != nil
            || setsTarget != nil
            || repsTarget != nil
            || repsLow != nil
            || repsHigh != nil

        if !hasUsefulValues {
            return removeExerciseDefault(for: exercise)
        }

        let model = fetchExerciseDefault(userId: userId, exerciseId: exercise.id) ?? {
            let created = ExerciseProgressionDefault(user_id: userId, exercise: exercise)
            modelContext.insert(created)
            return created
        }()

        model.exercise = exercise
        model.progression = progression
        model.setsTarget = setsTarget
        model.repsTarget = repsTarget
        model.repsLow = repsLow
        model.repsHigh = repsHigh
        model.timestamp = Date()
        return (try? modelContext.save()) != nil
    }

    @discardableResult
    func removeExerciseDefault(for exercise: Exercise) -> Bool {
        guard let userId = currentUser?.id else { return false }
        guard let model = fetchExerciseDefault(userId: userId, exerciseId: exercise.id) else { return true }
        modelContext.delete(model)
        return (try? modelContext.save()) != nil
    }

    private func fetchExerciseDefault(userId: UUID, exerciseId: UUID) -> ExerciseProgressionDefault? {
        let descriptor = FetchDescriptor<ExerciseProgressionDefault>()
        let matches = ((try? modelContext.fetch(descriptor)) ?? []).filter { model in
            model.user_id == userId && model.exercise?.id == exerciseId
        }
        return matches.sorted(by: { $0.id.uuidString < $1.id.uuidString }).first
    }

    private func fetchUserDefault(userId: UUID) -> UserProgressionDefault? {
        let descriptor = FetchDescriptor<UserProgressionDefault>()
        let matches = ((try? modelContext.fetch(descriptor)) ?? []).filter { model in
            model.user_id == userId
        }
        return matches.sorted(by: { $0.id.uuidString < $1.id.uuidString }).first
    }

    private func resolveSuggestedWeight(userId: UUID, exercise: Exercise, progression: ProgressionProfile?) -> Double? {
        if let progression {
            let stateDescriptor = FetchDescriptor<ProgressionState>()
            if let state = ((try? modelContext.fetch(stateDescriptor)) ?? []).first(where: { state in
                state.user_id == userId
                    && state.exercise?.id == exercise.id
                    && state.progression?.id == progression.id
            }),
               let workingWeight = state.workingWeight {
                return workingWeight
            }
        }

        if let fallbackRep = setService.mostRecentRep(for: exercise), fallbackRep.weight > 0 {
            return fallbackRep.weight
        }

        return nil
    }
}
