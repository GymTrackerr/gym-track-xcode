//
//  SyncingExerciseRepository.swift
//  GymTracker
//
//  Created by Codex on 2026-04-15.
//

import Foundation

final class ExerciseSyncRepository: BaseSyncRepository, ExerciseRepositoryProtocol {
    private let localRepository: ExerciseRepositoryProtocol
    private let payloadEncoder = JSONEncoder()

    init(
        localRepository: ExerciseRepositoryProtocol,
        queueStore: SyncQueueStore,
        eligibilityService: SyncEligibilityService
    ) {
        self.localRepository = localRepository
        super.init(queueStore: queueStore, eligibilityService: eligibilityService)
    }

    func fetchActiveExercises(for userId: UUID) throws -> [Exercise] {
        try localRepository.fetchActiveExercises(for: userId)
    }

    func fetchArchivedExercises(for userId: UUID) throws -> [Exercise] {
        try localRepository.fetchArchivedExercises(for: userId)
    }

    func applyCatalogExercises(
        _ data: [ExerciseDTO],
        for userId: UUID,
        allowInsert: Bool
    ) throws -> (inserted: Int, updated: Int, removed: Int) {
        try localRepository.applyCatalogExercises(data, for: userId, allowInsert: allowInsert)
    }

    func applyRemoteUserExercises(
        _ data: [GymTrackerExerciseDTO],
        for userId: UUID
    ) throws -> (inserted: Int, updated: Int, removed: Int) {
        try localRepository.applyRemoteUserExercises(data, for: userId)
    }

    func createExercise(name: String, type: ExerciseType, userId: UUID) throws -> Exercise {
        let exercise = try localRepository.createExercise(name: name, type: type, userId: userId)
        enqueueMutationIfNeeded(for: exercise, operation: .create)
        return exercise
    }

    func setAliases(_ aliases: [String], for exercise: Exercise) throws {
        try localRepository.setAliases(aliases, for: exercise)
        enqueueMutationIfNeeded(for: exercise, operation: .update)
    }

    func delete(_ exercise: Exercise) throws {
        try localRepository.delete(exercise)
        enqueueMutationIfNeeded(for: exercise, operation: .softDelete)
    }

    func restore(_ exercise: Exercise) throws {
        try localRepository.restore(exercise)
        enqueueMutationIfNeeded(for: exercise, operation: .restore)
    }

    func reinsertOrRestore(_ exercise: Exercise) throws {
        let operation: SyncQueueOperation = exercise.isArchived ? .restore : .create
        try localRepository.reinsertOrRestore(exercise)
        enqueueMutationIfNeeded(for: exercise, operation: operation)
    }

    func willArchiveOnDelete(_ exercise: Exercise) -> Bool {
        localRepository.willArchiveOnDelete(exercise)
    }

    func mergeExercisesWithSameNpId(for userId: UUID) throws -> ExerciseNpIdMergeReport {
        try localRepository.mergeExercisesWithSameNpId(for: userId)
    }

    func saveChanges() throws {
        try localRepository.saveChanges()
    }

    private func enqueueMutationIfNeeded(
        for exercise: Exercise,
        operation: SyncQueueOperation
    ) {
        guard exercise.isUserCreated else { return }

        do {
            let payload = try payloadEncoder.encode(ExerciseSyncPayload(exercise: exercise))
            let dependencyKey = "exercise:\(exercise.syncLinkedItemId)"
            enqueueRootMutationIfNeeded(
                root: exercise,
                operation: operation,
                payloadData: payload,
                dependencyKey: dependencyKey
            )
        } catch {
            print("Failed to encode sync payload for exercise \(exercise.id): \(error)")
        }
    }
}
