//
//  LocalProgramRepository.swift
//  GymTracker
//
//  Created by Codex on 2026-04-19.
//

import Foundation
import SwiftData

final class LocalProgramRepository: ProgramRepositoryProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchActivePrograms(for userId: UUID) throws -> [Program] {
        let descriptor = FetchDescriptor<Program>(
            predicate: #Predicate<Program> { program in
                program.user_id == userId && program.soft_deleted == false && program.isArchived == false
            }
        )
        let programs = try modelContext.fetch(descriptor)
        if try SyncRootMetadataManager.prepareForRead(programs, in: modelContext) {
            try modelContext.save()
        }
        return programs.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive {
                return lhs.isActive && !rhs.isActive
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    func fetchArchivedPrograms(for userId: UUID) throws -> [Program] {
        let descriptor = FetchDescriptor<Program>(
            predicate: #Predicate<Program> { program in
                program.user_id == userId && (program.soft_deleted == true || program.isArchived == true)
            }
        )
        let programs = try modelContext.fetch(descriptor)
        if try SyncRootMetadataManager.prepareForRead(programs, in: modelContext) {
            try modelContext.save()
        }
        return programs.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    func createProgram(
        userId: UUID,
        name: String,
        notes: String,
        mode: ProgramMode,
        startDate: Date,
        trainDaysBeforeRest: Int,
        restDays: Int
    ) throws -> Program {
        let program = Program(
            userId: userId,
            name: name,
            notes: notes,
            mode: mode,
            startDate: startDate,
            trainDaysBeforeRest: trainDaysBeforeRest,
            restDays: restDays
        )
        modelContext.insert(program)
        try SyncRootMetadataManager.markCreated(program, in: modelContext)
        try modelContext.save()
        return program
    }

    func saveChanges(for program: Program) throws {
        try SyncRootMetadataManager.markUpdated(program, in: modelContext)
        try modelContext.save()
    }

    func willArchiveOnDelete(_ program: Program) -> Bool {
        !program.sessions.isEmpty
    }

    func delete(_ program: Program) throws {
        if willArchiveOnDelete(program) {
            program.isArchived = true
            program.isActive = false
            program.soft_deleted = false
            try SyncRootMetadataManager.markUpdated(program, in: modelContext)
        } else {
            modelContext.delete(program)
        }
        try modelContext.save()
    }

    func restore(_ program: Program) throws {
        try SyncRootMetadataManager.markRestored(program, in: modelContext)
        try modelContext.save()
    }

    func setActiveProgram(_ program: Program?) throws {
        let activeUserId = program?.user_id
        let activeId = program?.id
        let descriptor: FetchDescriptor<Program>

        if let activeUserId {
            descriptor = FetchDescriptor<Program>(
                predicate: #Predicate<Program> { item in
                    item.user_id == activeUserId && item.soft_deleted == false
                }
            )
        } else {
            descriptor = FetchDescriptor<Program>(
                predicate: #Predicate<Program> { item in
                    item.isActive == true && item.soft_deleted == false
                }
            )
        }

        let candidates = try modelContext.fetch(descriptor)
        for candidate in candidates {
            let shouldBeActive = candidate.id == activeId
            if candidate.isActive != shouldBeActive {
                candidate.isActive = shouldBeActive
                try SyncRootMetadataManager.markUpdated(candidate, in: modelContext)
            }
        }
        try modelContext.save()
    }

    func addBlock(to program: Program, name: String?, durationCount: Int) throws -> ProgramBlock {
        let block = ProgramBlock(
            order: program.blocks.count,
            program: program,
            name: name,
            durationCount: durationCount
        )
        modelContext.insert(block)
        program.blocks.append(block)
        try SyncRootMetadataManager.markUpdated(program, in: modelContext)
        try modelContext.save()
        return block
    }

    func deleteBlock(_ block: ProgramBlock) throws {
        let program = block.program
        program.blocks.removeAll { $0.id == block.id }
        modelContext.delete(block)
        reorderBlocks(in: program)
        try SyncRootMetadataManager.markUpdated(program, in: modelContext)
        try modelContext.save()
    }

    func addWorkout(
        to block: ProgramBlock,
        routine: Routine?,
        name: String?,
        weekdayIndex: Int?
    ) throws -> ProgramWorkout {
        let workout = ProgramWorkout(
            order: block.workouts.count,
            programBlock: block,
            routine: routine,
            name: name,
            weekdayIndex: weekdayIndex
        )
        modelContext.insert(workout)
        block.workouts.append(workout)
        try SyncRootMetadataManager.markUpdated(block.program, in: modelContext)
        try modelContext.save()
        return workout
    }

    func deleteWorkout(_ workout: ProgramWorkout) throws {
        let block = workout.programBlock
        block.workouts.removeAll { $0.id == workout.id }
        modelContext.delete(workout)
        reorderWorkouts(in: block)
        try SyncRootMetadataManager.markUpdated(block.program, in: modelContext)
        try modelContext.save()
    }

    func moveWorkouts(in block: ProgramBlock, from source: IndexSet, to destination: Int) throws {
        var workouts = block.workouts.sorted { $0.order < $1.order }
        moveItems(in: &workouts, from: source, to: destination)
        for (index, workout) in workouts.enumerated() {
            workout.order = index
        }
        try SyncRootMetadataManager.markUpdated(block.program, in: modelContext)
        try modelContext.save()
    }

    private func reorderBlocks(in program: Program) {
        let blocks = program.blocks.sorted { $0.order < $1.order }
        for (index, block) in blocks.enumerated() {
            block.order = index
        }
    }

    private func reorderWorkouts(in block: ProgramBlock) {
        let workouts = block.workouts.sorted { $0.order < $1.order }
        for (index, workout) in workouts.enumerated() {
            workout.order = index
        }
    }

    private func moveItems(in workouts: inout [ProgramWorkout], from source: IndexSet, to destination: Int) {
        let movingItems = source.map { workouts[$0] }
        workouts.remove(atOffsets: source)

        var insertionIndex = destination
        let removedBeforeDestination = source.filter { $0 < destination }.count
        insertionIndex -= removedBeforeDestination
        insertionIndex = max(0, min(insertionIndex, workouts.count))

        workouts.insert(contentsOf: movingItems, at: insertionIndex)
    }
}

private extension Array {
    mutating func remove(atOffsets offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            remove(at: offset)
        }
    }
}
