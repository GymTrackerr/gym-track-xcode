//
//  ProgramRepositoryProtocol.swift
//  GymTracker
//
//  Created by Codex on 2026-04-19.
//

import Foundation

protocol ProgramRepositoryProtocol {
    func fetchActivePrograms(for userId: UUID) throws -> [Program]
    func fetchArchivedPrograms(for userId: UUID) throws -> [Program]
    func createProgram(
        userId: UUID,
        name: String,
        notes: String,
        mode: ProgramMode,
        startDate: Date,
        trainDaysBeforeRest: Int,
        restDays: Int
    ) throws -> Program
    func saveChanges(for program: Program) throws
    func delete(_ program: Program) throws
    func restore(_ program: Program) throws
    func setActiveProgram(_ program: Program?) throws
    func addBlock(to program: Program, name: String?, durationCount: Int) throws -> ProgramBlock
    func deleteBlock(_ block: ProgramBlock) throws
    func addWorkout(
        to block: ProgramBlock,
        routine: Routine?,
        name: String?,
        weekdayIndex: Int?
    ) throws -> ProgramWorkout
    func deleteWorkout(_ workout: ProgramWorkout) throws
    func moveWorkouts(in block: ProgramBlock, from source: IndexSet, to destination: Int) throws
}
