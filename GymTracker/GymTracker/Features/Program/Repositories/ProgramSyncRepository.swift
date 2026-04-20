//
//  ProgramSyncRepository.swift
//  GymTracker
//
//  Created by Codex on 2026-04-19.
//

import Foundation

final class ProgramSyncRepository: BaseSyncRepository, ProgramRepositoryProtocol {
    private let localRepository: ProgramRepositoryProtocol

    init(
        localRepository: ProgramRepositoryProtocol,
        queueStore: SyncQueueStore,
        eligibilityService: SyncEligibilityService
    ) {
        self.localRepository = localRepository
        super.init(queueStore: queueStore, eligibilityService: eligibilityService)
    }

    func fetchActivePrograms(for userId: UUID) throws -> [Program] { try localRepository.fetchActivePrograms(for: userId) }
    func fetchArchivedPrograms(for userId: UUID) throws -> [Program] { try localRepository.fetchArchivedPrograms(for: userId) }

    func createProgram(
        userId: UUID,
        name: String,
        notes: String,
        mode: ProgramMode,
        startDate: Date,
        trainDaysBeforeRest: Int,
        restDays: Int
    ) throws -> Program {
        let program = try localRepository.createProgram(
            userId: userId,
            name: name,
            notes: notes,
            mode: mode,
            startDate: startDate,
            trainDaysBeforeRest: trainDaysBeforeRest,
            restDays: restDays
        )
        enqueue(for: program, operation: .create)
        return program
    }

    func saveChanges(for program: Program) throws {
        try localRepository.saveChanges(for: program)
        enqueue(for: program, operation: .update)
    }

    func willArchiveOnDelete(_ program: Program) -> Bool {
        localRepository.willArchiveOnDelete(program)
    }

    func delete(_ program: Program) throws {
        let shouldArchive = localRepository.willArchiveOnDelete(program)
        try localRepository.delete(program)
        if shouldArchive {
            enqueue(for: program, operation: .softDelete)
        }
    }

    func restore(_ program: Program) throws {
        try localRepository.restore(program)
        enqueue(for: program, operation: .restore)
    }

    func setActiveProgram(_ program: Program?) throws {
        try localRepository.setActiveProgram(program)
        if let program {
            enqueue(for: program, operation: .update)
        }
    }

    func addBlock(to program: Program, name: String?, durationCount: Int) throws -> ProgramBlock {
        let block = try localRepository.addBlock(to: program, name: name, durationCount: durationCount)
        enqueue(for: block.program, operation: .update)
        return block
    }

    func deleteBlock(_ block: ProgramBlock) throws {
        let program = block.program
        try localRepository.deleteBlock(block)
        enqueue(for: program, operation: .update)
    }

    func addWorkout(
        to block: ProgramBlock,
        routine: Routine?,
        name: String?,
        weekdayIndex: Int?
    ) throws -> ProgramWorkout {
        let workout = try localRepository.addWorkout(to: block, routine: routine, name: name, weekdayIndex: weekdayIndex)
        enqueue(for: workout.programBlock.program, operation: .update)
        return workout
    }

    func deleteWorkout(_ workout: ProgramWorkout) throws {
        let program = workout.programBlock.program
        try localRepository.deleteWorkout(workout)
        enqueue(for: program, operation: .update)
    }

    func moveWorkouts(in block: ProgramBlock, from source: IndexSet, to destination: Int) throws {
        try localRepository.moveWorkouts(in: block, from: source, to: destination)
        enqueue(for: block.program, operation: .update)
    }

    private func enqueue(for program: Program, operation: SyncQueueOperation) {
        enqueueRootMutationIfNeeded(root: program, operation: operation)
    }
}
