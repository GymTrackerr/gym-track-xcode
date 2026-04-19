//
//  ProgramService.swift
//  GymTracker
//
//  Created by Codex on 2026-04-19.
//

import Foundation
import SwiftData
import Combine

struct ProgramResolvedState {
    let currentBlock: ProgramBlock?
    let nextWorkout: ProgramWorkout?
    let activeSession: Session?
    let blockLabel: String
    let progressLabel: String
    let scheduleLabel: String
    let nextWorkoutLabel: String
    let actionTitle: String
}

final class ProgramService: ServiceBase, ObservableObject {
    @Published var programs: [Program] = []
    @Published var archivedPrograms: [Program] = []

    private let repository: ProgramRepositoryProtocol

    init(context: ModelContext, repository: ProgramRepositoryProtocol? = nil) {
        self.repository = repository ?? LocalProgramRepository(modelContext: context)
        super.init(context: context)
    }

    override func loadFeature() {
        loadPrograms()
    }

    func loadPrograms() {
        guard let userId = currentUser?.id else {
            programs = []
            archivedPrograms = []
            return
        }

        do {
            programs = try repository.fetchActivePrograms(for: userId)
            archivedPrograms = try repository.fetchArchivedPrograms(for: userId)
        } catch {
            programs = []
            archivedPrograms = []
        }
    }

    var activeProgram: Program? {
        programs.first(where: { $0.isActive })
    }

    func isDirectWorkoutMode(_ program: Program) -> Bool {
        let blocks = sortedBlocks(for: program)
        guard let firstBlock = blocks.first else { return true }
        return blocks.count == 1 && firstBlock.isHiddenRepeatingBlock
    }

    func visibleBlocks(for program: Program) -> [ProgramBlock] {
        if isDirectWorkoutMode(program) {
            return []
        }
        return sortedBlocks(for: program)
    }

    func directWorkoutBlock(for program: Program) -> ProgramBlock? {
        let blocks = sortedBlocks(for: program)
        if let hiddenBlock = blocks.first(where: \.isHiddenRepeatingBlock) {
            return hiddenBlock
        }
        if blocks.count == 1 {
            return blocks.first
        }
        return nil
    }

    func directWorkouts(for program: Program) -> [ProgramWorkout] {
        guard let block = directWorkoutBlock(for: program) else { return [] }
        return sortedWorkouts(for: block)
    }

    @discardableResult
    func createProgram(
        name: String,
        notes: String = "",
        mode: ProgramMode,
        startDate: Date = Date(),
        trainDaysBeforeRest: Int = 3,
        restDays: Int = 1
    ) -> Program? {
        guard let userId = currentUser?.id else { return nil }

        do {
            let program = try repository.createProgram(
                userId: userId,
                name: name,
                notes: notes,
                mode: mode,
                startDate: startDate,
                trainDaysBeforeRest: trainDaysBeforeRest,
                restDays: restDays
            )
            _ = try ensureDirectWorkoutBlockExists(for: program)
            loadPrograms()
            return program
        } catch {
            print("Failed to create program: \(error)")
            return nil
        }
    }

    func saveChanges(for program: Program) {
        do {
            try repository.saveChanges(for: program)
            loadPrograms()
        } catch {
            print("Failed to save program changes: \(error)")
        }
    }

    func willArchiveOnDelete(_ program: Program) -> Bool {
        repository.willArchiveOnDelete(program)
    }

    func delete(_ program: Program) {
        do {
            try repository.delete(program)
            loadPrograms()
        } catch {
            print("Failed to delete program: \(error)")
        }
    }

    func restore(_ program: Program) {
        do {
            try repository.restore(program)
            loadPrograms()
        } catch {
            print("Failed to restore program: \(error)")
        }
    }

    func setActive(_ program: Program?) {
        do {
            try repository.setActiveProgram(program)
            loadPrograms()
        } catch {
            print("Failed to set active program: \(error)")
        }
    }

    @discardableResult
    func addBlock(to program: Program, name: String?, durationCount: Int) -> ProgramBlock? {
        do {
            if let hiddenBlock = hiddenRepeatingBlock(in: program) {
                hiddenBlock.name = sanitizedBlockName(name)
                hiddenBlock.durationCount = max(durationCount, 1)
                try repository.saveChanges(for: program)
                loadPrograms()
                return hiddenBlock
            }

            let block = try repository.addBlock(to: program, name: name, durationCount: durationCount)
            loadPrograms()
            return block
        } catch {
            print("Failed to add block: \(error)")
            return nil
        }
    }

    func deleteBlock(_ block: ProgramBlock) {
        do {
            let program = block.program
            try repository.deleteBlock(block)
            if hiddenRepeatingBlock(in: program) == nil, program.blocks.isEmpty {
                _ = try? ensureDirectWorkoutBlockExists(for: program)
            }
            loadPrograms()
        } catch {
            print("Failed to delete block: \(error)")
        }
    }

    @discardableResult
    func addWorkout(
        to block: ProgramBlock,
        routine: Routine?,
        name: String?,
        weekdayIndex: Int?
    ) -> ProgramWorkout? {
        do {
            let workout = try repository.addWorkout(
                to: block,
                routine: routine,
                name: name,
                weekdayIndex: weekdayIndex
            )
            loadPrograms()
            return workout
        } catch {
            print("Failed to add workout: \(error)")
            return nil
        }
    }

    func deleteWorkout(_ workout: ProgramWorkout) {
        do {
            try repository.deleteWorkout(workout)
            loadPrograms()
        } catch {
            print("Failed to delete workout: \(error)")
        }
    }

    func moveWorkouts(in block: ProgramBlock, from source: IndexSet, to destination: Int) {
        do {
            try repository.moveWorkouts(in: block, from: source, to: destination)
            loadPrograms()
        } catch {
            print("Failed to move workouts: \(error)")
        }
    }

    func moveWorkout(_ workout: ProgramWorkout, in block: ProgramBlock, direction: ProgramWorkoutMoveDirection) {
        let workouts = sortedWorkouts(for: block)
        guard let currentIndex = workouts.firstIndex(where: { $0.id == workout.id }) else { return }

        let source = IndexSet(integer: currentIndex)
        let destination: Int
        switch direction {
        case .up:
            guard currentIndex > 0 else { return }
            destination = currentIndex - 1
        case .down:
            guard currentIndex < workouts.count - 1 else { return }
            destination = currentIndex + 2
        }

        moveWorkouts(in: block, from: source, to: destination)
    }

    func canMoveWorkout(_ workout: ProgramWorkout, in block: ProgramBlock, direction: ProgramWorkoutMoveDirection) -> Bool {
        let workouts = sortedWorkouts(for: block)
        guard let currentIndex = workouts.firstIndex(where: { $0.id == workout.id }) else { return false }
        switch direction {
        case .up:
            return currentIndex > 0
        case .down:
            return currentIndex < workouts.count - 1
        }
    }

    func convertToBlocksMode(_ program: Program, initialBlockDurationCount: Int = 4) {
        guard let hiddenBlock = hiddenRepeatingBlock(in: program) else { return }
        hiddenBlock.name = nil
        hiddenBlock.durationCount = max(initialBlockDurationCount, 1)
        saveChanges(for: program)
    }

    func canConvertToDirectWorkoutMode(_ program: Program) -> Bool {
        let blocks = sortedBlocks(for: program)
        return blocks.count == 1 && !isDirectWorkoutMode(program)
    }

    func convertToDirectWorkoutMode(_ program: Program) {
        guard canConvertToDirectWorkoutMode(program),
              let block = sortedBlocks(for: program).first else {
            return
        }

        block.name = ProgramBlock.hiddenRepeatingBlockSentinel
        block.durationCount = 0
        saveChanges(for: program)
    }

    func copyWorkouts(from sourceBlock: ProgramBlock, to destinationBlock: ProgramBlock) {
        let workouts = sortedWorkouts(for: sourceBlock)
        guard !workouts.isEmpty else { return }

        for workout in workouts {
            _ = addWorkout(
                to: destinationBlock,
                routine: workout.routine,
                name: workout.name,
                weekdayIndex: workout.weekdayIndex
            )
        }
    }

    func resolvedState(
        for program: Program,
        sessions: [Session],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> ProgramResolvedState {
        let sortedBlocks = sortedBlocks(for: program)
        guard !sortedBlocks.isEmpty else {
            return ProgramResolvedState(
                currentBlock: nil,
                nextWorkout: nil,
                activeSession: nil,
                blockLabel: "Workout Rotation",
                progressLabel: "Add workouts to begin",
                scheduleLabel: program.scheduleSummary,
                nextWorkoutLabel: "Add a workout",
                actionTitle: "Add Workout"
            )
        }

        let relevantSessions = sessions
            .filter { !$0.soft_deleted && $0.program?.id == program.id }
            .sorted { $0.timestamp < $1.timestamp }

        let activeSession = relevantSessions.last {
            $0.timestampDone == $0.timestamp
        }

        switch program.mode {
        case .weekly:
            return resolveWeeklyState(
                for: program,
                blocks: sortedBlocks,
                sessions: relevantSessions,
                activeSession: activeSession,
                referenceDate: referenceDate,
                calendar: calendar
            )
        case .continuous:
            return resolveContinuousState(
                for: program,
                blocks: sortedBlocks,
                sessions: relevantSessions,
                activeSession: activeSession
            )
        }
    }

    private func resolveWeeklyState(
        for program: Program,
        blocks: [ProgramBlock],
        sessions: [Session],
        activeSession: Session?,
        referenceDate: Date,
        calendar: Calendar
    ) -> ProgramResolvedState {
        let block = currentWeeklyBlock(for: program, blocks: blocks, referenceDate: referenceDate, calendar: calendar)
        let nextWorkout = activeSession.flatMap { matchingWorkout(for: $0, in: block) } ?? nextWeeklyWorkout(in: block, referenceDate: referenceDate, calendar: calendar)
        let weekLabel = weeklyProgressLabel(for: program, block: block, referenceDate: referenceDate, calendar: calendar)

        return ProgramResolvedState(
            currentBlock: block,
            nextWorkout: nextWorkout,
            activeSession: activeSession,
            blockLabel: blockLabel(for: block),
            progressLabel: weekLabel,
            scheduleLabel: nextWorkout?.scheduleLabel ?? program.scheduleSummary,
            nextWorkoutLabel: nextWorkout?.displayName ?? "No workout",
            actionTitle: activeSession == nil ? "Start Next Workout" : "Resume Current Workout"
        )
    }

    private func resolveContinuousState(
        for program: Program,
        blocks: [ProgramBlock],
        sessions: [Session],
        activeSession: Session?
    ) -> ProgramResolvedState {
        let completedSessions = sessions.filter { $0.timestampDone != $0.timestamp }

        if let activeSession,
           let block = blocks.first(where: { $0.id == activeSession.programBlockId }) ?? blocks.first,
           let workout = matchingWorkout(for: activeSession, in: block) {
            return ProgramResolvedState(
                currentBlock: block,
                nextWorkout: workout,
                activeSession: activeSession,
                blockLabel: blockLabel(for: block),
                progressLabel: continuousProgressLabel(for: block, completedSessions: completedSessions),
                scheduleLabel: program.scheduleSummary,
                nextWorkoutLabel: workout.displayName,
                actionTitle: "Resume Current Workout"
            )
        }

        for block in blocks {
            let workouts = block.workouts.sorted { $0.order < $1.order }
            guard !workouts.isEmpty else {
                return ProgramResolvedState(
                    currentBlock: block,
                    nextWorkout: nil,
                    activeSession: nil,
                    blockLabel: blockLabel(for: block),
                    progressLabel: "No workouts yet",
                    scheduleLabel: program.scheduleSummary,
                    nextWorkoutLabel: "Add a workout",
                    actionTitle: "Add Workout"
                )
            }

            let completedCount = completedSessions.filter { $0.programBlockId == block.id }.count
            let completedPasses = completedCount / workouts.count

            if block.repeatsForever || completedPasses < block.durationCount {
                let nextWorkout = workouts[completedCount % workouts.count]
                return ProgramResolvedState(
                    currentBlock: block,
                    nextWorkout: nextWorkout,
                    activeSession: nil,
                    blockLabel: blockLabel(for: block),
                    progressLabel: continuousProgressLabel(for: block, completedSessions: completedSessions),
                    scheduleLabel: program.scheduleSummary,
                    nextWorkoutLabel: nextWorkout.displayName,
                    actionTitle: "Start Next Workout"
                )
            }
        }

        let fallbackBlock = blocks.last
        let fallbackWorkout = fallbackBlock?.workouts.sorted { $0.order < $1.order }.first

        return ProgramResolvedState(
            currentBlock: fallbackBlock,
            nextWorkout: fallbackWorkout,
            activeSession: nil,
            blockLabel: blockLabel(for: fallbackBlock),
            progressLabel: "Completed",
            scheduleLabel: program.scheduleSummary,
            nextWorkoutLabel: fallbackWorkout?.displayName ?? "No workout",
            actionTitle: "Start Workout"
        )
    }

    private func currentWeeklyBlock(
        for program: Program,
        blocks: [ProgramBlock],
        referenceDate: Date,
        calendar: Calendar
    ) -> ProgramBlock? {
        let startDate = calendar.startOfDay(for: program.startDate)
        let today = calendar.startOfDay(for: referenceDate)
        let dayOffset = max(calendar.dateComponents([.day], from: startDate, to: today).day ?? 0, 0)
        let elapsedWeeks = dayOffset / 7

        var consumedWeeks = 0
        for block in blocks {
            if block.repeatsForever {
                return block
            }
            let blockDuration = max(block.durationCount, 1)
            if elapsedWeeks < consumedWeeks + blockDuration {
                return block
            }
            consumedWeeks += blockDuration
        }

        return blocks.last
    }

    private func weeklyProgressLabel(
        for program: Program,
        block: ProgramBlock?,
        referenceDate: Date,
        calendar: Calendar
    ) -> String {
        guard let block else { return "No block" }
        if block.repeatsForever {
            return "Repeats weekly"
        }

        let blocks = sortedBlocks(for: program)
        let startDate = calendar.startOfDay(for: program.startDate)
        let today = calendar.startOfDay(for: referenceDate)
        let dayOffset = max(calendar.dateComponents([.day], from: startDate, to: today).day ?? 0, 0)
        let elapsedWeeks = dayOffset / 7

        let previousWeeks = blocks
            .filter { $0.order < block.order }
            .reduce(0) { $0 + max($1.durationCount, 1) }

        let weekInBlock = min(max((elapsedWeeks - previousWeeks) + 1, 1), max(block.durationCount, 1))
        return "Week \(weekInBlock) of \(max(block.durationCount, 1))"
    }

    private func nextWeeklyWorkout(
        in block: ProgramBlock?,
        referenceDate: Date,
        calendar: Calendar
    ) -> ProgramWorkout? {
        guard let block else { return nil }

        let workouts = block.workouts.sorted { lhs, rhs in
            let leftDay = lhs.weekdayIndex ?? Int.max
            let rightDay = rhs.weekdayIndex ?? Int.max
            if leftDay == rightDay {
                return lhs.order < rhs.order
            }
            return leftDay < rightDay
        }

        guard !workouts.isEmpty else { return nil }
        let weekdayIndex = ProgramWeekday.mondayBasedIndex(for: referenceDate, calendar: calendar)
        return workouts.first(where: { ($0.weekdayIndex ?? weekdayIndex) >= weekdayIndex }) ?? workouts.first
    }

    private func continuousProgressLabel(for block: ProgramBlock, completedSessions: [Session]) -> String {
        let workoutsCount = max(block.workouts.count, 1)
        let completedCount = completedSessions.filter { $0.programBlockId == block.id }.count
        let completedPasses = completedCount / workoutsCount
        if block.repeatsForever {
            return "Split \(completedPasses + 1)"
        }
        return "Split \(min(completedPasses + 1, block.durationCount)) of \(block.durationCount)"
    }

    private func matchingWorkout(for session: Session, in block: ProgramBlock?) -> ProgramWorkout? {
        guard let block else { return nil }
        if let workoutId = session.programWorkoutId {
            return block.workouts.first(where: { $0.id == workoutId })
        }
        return sortedWorkouts(for: block).first
    }

    private func sortedBlocks(for program: Program) -> [ProgramBlock] {
        program.blocks.sorted { lhs, rhs in
            if lhs.order == rhs.order {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.order < rhs.order
        }
    }

    private func sortedWorkouts(for block: ProgramBlock) -> [ProgramWorkout] {
        block.workouts.sorted { lhs, rhs in
            if lhs.order == rhs.order {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.order < rhs.order
        }
    }

    private func hiddenRepeatingBlock(in program: Program) -> ProgramBlock? {
        sortedBlocks(for: program).first(where: \.isHiddenRepeatingBlock)
    }

    private func ensureDirectWorkoutBlockExists(for program: Program) throws -> ProgramBlock {
        if let existing = hiddenRepeatingBlock(in: program) {
            return existing
        }

        if let singleBlock = sortedBlocks(for: program).first, program.blocks.count == 1 {
            return singleBlock
        }

        return try repository.addBlock(
            to: program,
            name: ProgramBlock.hiddenRepeatingBlockSentinel,
            durationCount: 0
        )
    }

    private func sanitizedBlockName(_ name: String?) -> String? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func blockLabel(for block: ProgramBlock?) -> String {
        guard let block else { return "No block" }
        if block.isHiddenRepeatingBlock {
            return "Workout Rotation"
        }
        return block.displayName
    }
}

enum ProgramWorkoutMoveDirection {
    case up
    case down
}
