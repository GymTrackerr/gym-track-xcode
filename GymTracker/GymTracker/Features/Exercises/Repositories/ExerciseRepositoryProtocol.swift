//
//  ExerciseRepositoryProtocol.swift
//  GymTracker
//
//  Created by Codex on 2026-04-15.
//

import Foundation

struct ExerciseNpIdMergeReport {
    let groupsMerged: Int
    let duplicatesRemoved: Int
}

protocol ExerciseRepositoryProtocol {
    func fetchActiveExercises(for userId: UUID) throws -> [Exercise]
    func fetchArchivedExercises(for userId: UUID) throws -> [Exercise]
    func applyCatalogExercises(
        _ data: [ExerciseDTO],
        for userId: UUID,
        allowInsert: Bool
    ) throws -> (inserted: Int, updated: Int, removed: Int)
    func createExercise(name: String, type: ExerciseType, userId: UUID) throws -> Exercise
    func setAliases(_ aliases: [String], for exercise: Exercise) throws
    func delete(_ exercise: Exercise) throws
    func restore(_ exercise: Exercise) throws
    func reinsertOrRestore(_ exercise: Exercise) throws
    func willArchiveOnDelete(_ exercise: Exercise) -> Bool
    func mergeExercisesWithSameNpId(for userId: UUID) throws -> ExerciseNpIdMergeReport
    func saveChanges() throws
}
