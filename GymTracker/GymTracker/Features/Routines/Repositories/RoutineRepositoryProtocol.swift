//
//  RoutineRepositoryProtocol.swift
//  GymTracker
//
//  Created by Codex on 2026-04-15.
//

import Foundation

protocol RoutineRepositoryProtocol {
    func fetchActiveRoutines(for userId: UUID) throws -> [Routine]
    func fetchArchivedRoutines(for userId: UUID) throws -> [Routine]
    func fetchAllRoutines() throws -> [Routine]
    func createRoutine(name: String, userId: UUID, order: Int) throws -> Routine
    func setAliases(_ aliases: [String], for routine: Routine) throws
    func reinsertOrRestore(_ routine: Routine) throws
    func delete(_ routine: Routine) throws
    func restore(_ routine: Routine) throws
    func willArchiveOnDelete(_ routine: Routine) -> Bool
    func renumber(_ routines: [Routine]) throws
    func renumberExerciseSplits(in routine: Routine) throws
    func addExercise(to routine: Routine, exercise: Exercise) throws -> ExerciseSplitDay?
    func removeExercise(from routine: Routine, exercise: Exercise) throws
    func removeExerciseSplits(from routine: Routine, splitIds: [UUID]) throws
    func moveExercises(in routine: Routine, from source: IndexSet, to destination: Int) throws
    func reinsertExerciseSplit(_ exerciseSplit: ExerciseSplitDay, into routine: Routine) throws
    func saveChanges() throws
}
