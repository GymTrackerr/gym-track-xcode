//
//  ProgressionSyncRepository.swift
//  GymTracker
//
//  Created by Codex on 2026-04-19.
//

import Foundation

final class ProgressionSyncRepository: BaseSyncRepository, ProgressionRepositoryProtocol {
    private let localRepository: ProgressionRepositoryProtocol

    init(
        localRepository: ProgressionRepositoryProtocol,
        queueStore: SyncQueueStore,
        eligibilityService: SyncEligibilityService
    ) {
        self.localRepository = localRepository
        super.init(queueStore: queueStore, eligibilityService: eligibilityService)
    }

    func fetchAvailableProfiles(for userId: UUID?) throws -> [ProgressionProfile] { try localRepository.fetchAvailableProfiles(for: userId) }
    func fetchArchivedProfiles(for userId: UUID?) throws -> [ProgressionProfile] { try localRepository.fetchArchivedProfiles(for: userId) }
    func fetchProfile(id: UUID) throws -> ProgressionProfile? { try localRepository.fetchProfile(id: id) }

    func upsertBuiltInProfile(
        name: String,
        miniDescription: String,
        type: ProgressionType,
        incrementValue: Double,
        percentageIncrease: Double,
        incrementUnit: WeightUnit,
        setIncrement: Int,
        successThreshold: Int,
        defaultSetsTarget: Int,
        defaultRepsTarget: Int?,
        defaultRepsLow: Int?,
        defaultRepsHigh: Int?
    ) throws -> ProgressionProfile {
        let profile = try localRepository.upsertBuiltInProfile(
            name: name,
            miniDescription: miniDescription,
            type: type,
            incrementValue: incrementValue,
            percentageIncrease: percentageIncrease,
            incrementUnit: incrementUnit,
            setIncrement: setIncrement,
            successThreshold: successThreshold,
            defaultSetsTarget: defaultSetsTarget,
            defaultRepsTarget: defaultRepsTarget,
            defaultRepsLow: defaultRepsLow,
            defaultRepsHigh: defaultRepsHigh
        )
        enqueue(profile, operation: .update)
        return profile
    }

    func createProfile(
        userId: UUID,
        name: String,
        miniDescription: String,
        type: ProgressionType,
        incrementValue: Double,
        percentageIncrease: Double,
        incrementUnit: WeightUnit,
        setIncrement: Int,
        successThreshold: Int,
        defaultSetsTarget: Int,
        defaultRepsTarget: Int?,
        defaultRepsLow: Int?,
        defaultRepsHigh: Int?
    ) throws -> ProgressionProfile {
        let profile = try localRepository.createProfile(
            userId: userId,
            name: name,
            miniDescription: miniDescription,
            type: type,
            incrementValue: incrementValue,
            percentageIncrease: percentageIncrease,
            incrementUnit: incrementUnit,
            setIncrement: setIncrement,
            successThreshold: successThreshold,
            defaultSetsTarget: defaultSetsTarget,
            defaultRepsTarget: defaultRepsTarget,
            defaultRepsLow: defaultRepsLow,
            defaultRepsHigh: defaultRepsHigh
        )
        enqueue(profile, operation: .create)
        return profile
    }

    func saveChanges(for profile: ProgressionProfile) throws {
        try localRepository.saveChanges(for: profile)
        enqueue(profile, operation: .update)
    }

    func delete(_ profile: ProgressionProfile) throws {
        try localRepository.delete(profile)
        enqueue(profile, operation: .softDelete)
    }

    func fetchProgressionExercises(for userId: UUID) throws -> [ProgressionExercise] {
        try localRepository.fetchProgressionExercises(for: userId)
    }

    func fetchProgressionExercise(for userId: UUID, exerciseId: UUID) throws -> ProgressionExercise? {
        try localRepository.fetchProgressionExercise(for: userId, exerciseId: exerciseId)
    }

    func createProgressionExercise(
        userId: UUID,
        exercise: Exercise,
        profile: ProgressionProfile?,
        assignmentSource: ProgressionAssignmentSource,
        targetSetCount: Int,
        targetReps: Int?,
        targetRepsLow: Int?,
        targetRepsHigh: Int?
    ) throws -> ProgressionExercise {
        let progressionExercise = try localRepository.createProgressionExercise(
            userId: userId,
            exercise: exercise,
            profile: profile,
            assignmentSource: assignmentSource,
            targetSetCount: targetSetCount,
            targetReps: targetReps,
            targetRepsLow: targetRepsLow,
            targetRepsHigh: targetRepsHigh
        )
        enqueue(progressionExercise, operation: .create)
        return progressionExercise
    }

    func saveChanges(for progressionExercise: ProgressionExercise) throws {
        try localRepository.saveChanges(for: progressionExercise)
        enqueue(progressionExercise, operation: .update)
    }

    func delete(_ progressionExercise: ProgressionExercise) throws {
        try localRepository.delete(progressionExercise)
        enqueue(progressionExercise, operation: .softDelete)
    }

    private func enqueue(_ profile: ProgressionProfile, operation: SyncQueueOperation) {
        enqueueRootMutationIfNeeded(root: profile, operation: operation)
    }

    private func enqueue(_ progressionExercise: ProgressionExercise, operation: SyncQueueOperation) {
        enqueueRootMutationIfNeeded(root: progressionExercise, operation: operation)
    }
}
