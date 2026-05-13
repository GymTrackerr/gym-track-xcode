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
    let recentCompletedSession: Session?
    let blockLabel: String
    let progressLabel: String
    let scheduleLabel: String
    let nextWorkoutLabel: String
    let actionTitle: String
    let canStartNextWorkout: Bool
    let canSkipNextWorkout: Bool
    let shouldShowDashboardStartAction: Bool
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

    func refreshWidgetSnapshot(sessions: [Session], reloadTimelines: Bool = true) {
        guard let currentUser else {
            ProgrammeWidgetSnapshotService().clear(reloadTimelines: reloadTimelines)
            return
        }

        let userSessions = sessions
            .filter { !$0.soft_deleted && $0.user_id == currentUser.id }
        let activeSession = userSessions
            .filter { $0.timestampDone == $0.timestamp }
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp > rhs.timestamp
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .first
        let program = activeProgram
        let state = program.map { resolvedState(for: $0, sessions: userSessions) }

        ProgrammeWidgetSnapshotService().refresh(
            user: currentUser,
            activeProgram: program,
            state: state,
            activeSession: activeSession ?? state?.activeSession,
            reloadTimelines: reloadTimelines
        )
    }

    func workoutCount(for program: Program) -> Int {
        sortedBlocks(for: program).reduce(0) { partialResult, block in
            partialResult + block.workouts.count
        }
    }

    func completedSessions(
        for program: Program,
        sessions: [Session]
    ) -> [Session] {
        sessions
            .filter { !$0.soft_deleted && $0.program?.id == program.id && $0.timestampDone != $0.timestamp }
            .sorted { lhs, rhs in
                if lhs.timestampDone != rhs.timestampDone {
                    return lhs.timestampDone > rhs.timestampDone
                }
                return lhs.timestamp > rhs.timestamp
            }
    }

    func nextDueSummary(
        for program: Program,
        sessions: [Session],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let state = resolvedState(
            for: program,
            sessions: sessions,
            referenceDate: referenceDate,
            calendar: calendar
        )

        if state.activeSession != nil {
            return "Now"
        }

        switch program.mode {
        case .continuous:
            return continuousDueSummary(
                for: program,
                state: state,
                sessions: sessions,
                referenceDate: referenceDate,
                calendar: calendar
            )
        case .weekly:
            return weeklyDueSummary(
                for: program,
                state: state,
                sessions: sessions,
                referenceDate: referenceDate,
                calendar: calendar
            )
        }
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

    func skipNextWorkout(
        for program: Program,
        sessions: [Session],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) {
        let state = resolvedState(
            for: program,
            sessions: sessions,
            referenceDate: referenceDate,
            calendar: calendar
        )

        guard state.activeSession == nil else { return }
        guard let nextWorkout = state.nextWorkout else { return }

        switch program.mode {
        case .continuous:
            program.continuousSkippedWorkoutCount += 1
        case .weekly:
            let weekOffset = currentProgramWeekOffset(
                for: program,
                referenceDate: referenceDate,
                calendar: calendar
            )
            let nextOverride = nextWorkoutAfter(
                nextWorkout,
                in: orderedWeeklyWorkouts(for: state.currentBlock)
            )
            program.weeklySkipWeekOffset = weekOffset
            program.weeklySkipNextWorkoutId = nextOverride?.id
        }

        persistCursorChanges(for: program)
        loadPrograms()
    }

    func handleFinishedSession(_ session: Session, calendar: Calendar = .current) {
        guard let program = session.program else { return }
        var didMutate = sanitizeSkipState(for: program, referenceDate: session.timestampDone, calendar: calendar)

        if program.mode == .weekly,
           program.weeklySkipWeekOffset == currentProgramWeekOffset(
                for: program,
                referenceDate: session.timestampDone,
                calendar: calendar
           ) {
            program.weeklySkipWeekOffset = nil
            program.weeklySkipNextWorkoutId = nil
            didMutate = true
        }

        if didMutate {
            persistCursorChanges(for: program)
            loadPrograms()
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
                routine: routineForWorkout(workout),
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
        let didSanitize = sanitizeSkipState(for: program, referenceDate: referenceDate, calendar: calendar)
        if didSanitize {
            persistCursorChanges(for: program)
        }

        let sortedBlocks = sortedBlocks(for: program)
        let relevantSessions = sessions
            .filter { !$0.soft_deleted && $0.program?.id == program.id }
            .sorted { $0.timestamp < $1.timestamp }
        let activeSession = relevantSessions.last {
            $0.timestampDone == $0.timestamp
        }
        let recentCompletedSession = relevantSessions
            .filter { $0.timestampDone != $0.timestamp }
            .max(by: { lhs, rhs in
                if lhs.timestampDone != rhs.timestampDone {
                    return lhs.timestampDone < rhs.timestampDone
                }
                return lhs.timestamp < rhs.timestamp
            })

        guard !sortedBlocks.isEmpty else {
            return ProgramResolvedState(
                currentBlock: nil,
                nextWorkout: nil,
                activeSession: nil,
                recentCompletedSession: recentCompletedSession,
                blockLabel: workoutRotationLabel,
                progressLabel: addWorkoutsToBeginLabel,
                scheduleLabel: program.scheduleSummary,
                nextWorkoutLabel: addWorkoutLabel,
                actionTitle: addWorkoutLabel,
                canStartNextWorkout: false,
                canSkipNextWorkout: false,
                shouldShowDashboardStartAction: false
            )
        }

        switch program.mode {
        case .weekly:
            return resolveWeeklyState(
                for: program,
                blocks: sortedBlocks,
                sessions: relevantSessions,
                activeSession: activeSession,
                recentCompletedSession: recentCompletedSession,
                referenceDate: referenceDate,
                calendar: calendar
            )
        case .continuous:
            return resolveContinuousState(
                for: program,
                blocks: sortedBlocks,
                sessions: relevantSessions,
                activeSession: activeSession,
                recentCompletedSession: recentCompletedSession,
                referenceDate: referenceDate,
                calendar: calendar
            )
        }
    }

    private func resolveWeeklyState(
        for program: Program,
        blocks: [ProgramBlock],
        sessions: [Session],
        activeSession: Session?,
        recentCompletedSession: Session?,
        referenceDate: Date,
        calendar: Calendar
    ) -> ProgramResolvedState {
        let block = currentWeeklyBlock(for: program, blocks: blocks, referenceDate: referenceDate, calendar: calendar)
        let nextWorkout = activeSession.flatMap { matchingWorkout(for: $0, in: block) } ??
            nextWeeklyWorkout(
                for: program,
                in: block,
                sessions: sessions,
                referenceDate: referenceDate,
                calendar: calendar
            )
        let weekLabel = weeklyProgressLabel(for: program, block: block, referenceDate: referenceDate, calendar: calendar)
        let canStartNextWorkout = activeSession != nil || nextWorkout.map { isWorkoutStartable($0) } == true
        let canSkipNextWorkout = activeSession == nil && nextWorkout != nil
        let shouldShowDashboardStartAction: Bool
        if activeSession != nil {
            shouldShowDashboardStartAction = true
        } else if let nextWorkout {
            let todayIndex = ProgramWeekday.mondayBasedIndex(for: referenceDate, calendar: calendar)
            shouldShowDashboardStartAction = nextWorkout.weekdayIndex == todayIndex && isWorkoutStartable(nextWorkout)
        } else {
            shouldShowDashboardStartAction = false
        }

        return ProgramResolvedState(
            currentBlock: block,
            nextWorkout: nextWorkout,
            activeSession: activeSession,
            recentCompletedSession: recentCompletedSession,
            blockLabel: blockLabel(for: block),
            progressLabel: weekLabel,
            scheduleLabel: nextWorkout?.scheduleLabel ?? program.scheduleSummary,
            nextWorkoutLabel: nextWorkout?.displayName ?? allWorkoutsCompletedThisWeekLabel,
            actionTitle: activeSession == nil ? (nextWorkout == nil ? workoutCompleteLabel : startNextWorkoutLabel) : resumeCurrentWorkoutLabel,
            canStartNextWorkout: canStartNextWorkout,
            canSkipNextWorkout: canSkipNextWorkout,
            shouldShowDashboardStartAction: shouldShowDashboardStartAction
        )
    }

    private func resolveContinuousState(
        for program: Program,
        blocks: [ProgramBlock],
        sessions: [Session],
        activeSession: Session?,
        recentCompletedSession: Session?,
        referenceDate: Date,
        calendar: Calendar
    ) -> ProgramResolvedState {
        let completedSessions = sessions.filter { $0.timestampDone != $0.timestamp }
        let completedToday = recentCompletedSession.map {
            calendar.isDate($0.timestampDone, inSameDayAs: referenceDate)
        } ?? false

        if let activeSession,
           let block = blocks.first(where: { $0.id == activeSession.programBlockId }) ?? blocks.first,
           let workout = matchingWorkout(for: activeSession, in: block) {
            let consumedWithinBlock = continuousConsumedWorkoutCount(
                in: block,
                for: program,
                blocks: blocks,
                completedSessions: completedSessions
            )
            return ProgramResolvedState(
                currentBlock: block,
                nextWorkout: workout,
                activeSession: activeSession,
                recentCompletedSession: recentCompletedSession,
                blockLabel: blockLabel(for: block),
                progressLabel: continuousProgressLabel(for: block, consumedWorkoutCount: consumedWithinBlock),
                scheduleLabel: program.scheduleSummary,
                nextWorkoutLabel: workout.displayName,
                actionTitle: resumeCurrentWorkoutLabel,
                canStartNextWorkout: true,
                canSkipNextWorkout: false,
                shouldShowDashboardStartAction: true
            )
        }

        var remainingConsumedCount = max(program.continuousSkippedWorkoutCount, 0) + completedSessions.count

        for block in blocks {
            let workouts = block.workouts.sorted { $0.order < $1.order }
            guard !workouts.isEmpty else {
                return ProgramResolvedState(
                    currentBlock: block,
                    nextWorkout: nil,
                    activeSession: nil,
                    recentCompletedSession: recentCompletedSession,
                    blockLabel: blockLabel(for: block),
                    progressLabel: noWorkoutsYetLabel,
                    scheduleLabel: program.scheduleSummary,
                    nextWorkoutLabel: addWorkoutLabel,
                    actionTitle: addWorkoutLabel,
                    canStartNextWorkout: false,
                    canSkipNextWorkout: false,
                    shouldShowDashboardStartAction: false
                )
            }

            let blockCapacity = block.repeatsForever ? Int.max : max(block.durationCount, 1) * workouts.count
            if block.repeatsForever || remainingConsumedCount < blockCapacity {
                let consumedWithinBlock = remainingConsumedCount
                let nextWorkout = workouts[consumedWithinBlock % workouts.count]
                return ProgramResolvedState(
                    currentBlock: block,
                    nextWorkout: nextWorkout,
                    activeSession: nil,
                    recentCompletedSession: recentCompletedSession,
                    blockLabel: blockLabel(for: block),
                    progressLabel: continuousProgressLabel(for: block, consumedWorkoutCount: consumedWithinBlock),
                    scheduleLabel: program.scheduleSummary,
                    nextWorkoutLabel: nextWorkout.displayName,
                    actionTitle: startNextWorkoutLabel,
                    canStartNextWorkout: isWorkoutStartable(nextWorkout),
                    canSkipNextWorkout: true,
                    shouldShowDashboardStartAction: isWorkoutStartable(nextWorkout) && !completedToday
                )
            }

            remainingConsumedCount -= blockCapacity
        }

        let fallbackBlock = blocks.last
        let fallbackWorkout = fallbackBlock?.workouts.sorted { $0.order < $1.order }.first

        return ProgramResolvedState(
            currentBlock: fallbackBlock,
            nextWorkout: fallbackWorkout,
            activeSession: nil,
            recentCompletedSession: recentCompletedSession,
            blockLabel: blockLabel(for: fallbackBlock),
            progressLabel: completedLabel,
            scheduleLabel: program.scheduleSummary,
            nextWorkoutLabel: fallbackWorkout?.displayName ?? noWorkoutLabel,
            actionTitle: workoutCompleteLabel,
            canStartNextWorkout: false,
            canSkipNextWorkout: false,
            shouldShowDashboardStartAction: false
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
        guard let block else { return noBlockLabel }
        if block.repeatsForever {
            return String(localized: LocalizedStringResource(
                "programmes.state.repeatsWeekly",
                defaultValue: "Repeats weekly",
                table: "Programmes"
            ))
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
        let duration = max(block.durationCount, 1)
        return String(localized: LocalizedStringResource(
            "programmes.state.weekOf",
            defaultValue: "Week \(weekInBlock) of \(duration)",
            table: "Programmes"
        ))
    }

    private func nextWeeklyWorkout(
        for program: Program,
        in block: ProgramBlock?,
        sessions: [Session],
        referenceDate: Date,
        calendar: Calendar
    ) -> ProgramWorkout? {
        guard let block else { return nil }
        let workouts = orderedWeeklyWorkouts(for: block)
        guard !workouts.isEmpty else { return nil }

        let weekOffset = currentProgramWeekOffset(for: program, referenceDate: referenceDate, calendar: calendar)
        let weekRange = currentProgramWeekRange(for: program, referenceDate: referenceDate, calendar: calendar)
        let completedSessions = sessions
            .filter { $0.timestampDone != $0.timestamp }
            .filter { $0.programBlockId == block.id }
            .filter { weekRange.contains($0.timestamp) }
            .sorted { lhs, rhs in
                if lhs.timestampDone != rhs.timestampDone {
                    return lhs.timestampDone < rhs.timestampDone
                }
                return lhs.timestamp < rhs.timestamp
            }

        if let overrideWeek = program.weeklySkipWeekOffset,
           overrideWeek == weekOffset {
            guard let overrideWorkoutId = program.weeklySkipNextWorkoutId else {
                return nil
            }
            if let overrideWorkout = workouts.first(where: { $0.id == overrideWorkoutId }) {
                if let latestCompletedWorkout = completedSessions.last.flatMap({ matchingWorkout(for: $0, in: block) }),
                   let latestIndex = workouts.firstIndex(where: { $0.id == latestCompletedWorkout.id }),
                   let overrideIndex = workouts.firstIndex(where: { $0.id == overrideWorkout.id }),
                   overrideIndex <= latestIndex {
                    return nextWorkoutAfter(latestCompletedWorkout, in: workouts)
                }
                return overrideWorkout
            }
        }

        if let latestCompletedWorkout = completedSessions.last.flatMap({ matchingWorkout(for: $0, in: block) }) {
            return nextWorkoutAfter(latestCompletedWorkout, in: workouts)
        }

        let weekdayIndex = ProgramWeekday.mondayBasedIndex(for: referenceDate, calendar: calendar)
        return workouts.first(where: { ($0.weekdayIndex ?? weekdayIndex) >= weekdayIndex }) ?? workouts.first
    }

    private func continuousProgressLabel(for block: ProgramBlock, consumedWorkoutCount: Int) -> String {
        let workoutsCount = max(block.workouts.count, 1)
        let completedPasses = consumedWorkoutCount / workoutsCount
        if block.repeatsForever {
            let split = completedPasses + 1
            return String(localized: LocalizedStringResource(
                "programmes.state.split",
                defaultValue: "Split \(split)",
                table: "Programmes"
            ))
        }
        let split = min(completedPasses + 1, block.durationCount)
        return String(localized: LocalizedStringResource(
            "programmes.state.splitOf",
            defaultValue: "Split \(split) of \(block.durationCount)",
            table: "Programmes"
        ))
    }

    private func currentProgramWeekOffset(
        for program: Program,
        referenceDate: Date,
        calendar: Calendar
    ) -> Int {
        let startDate = calendar.startOfDay(for: program.startDate)
        let today = calendar.startOfDay(for: referenceDate)
        let dayOffset = max(calendar.dateComponents([.day], from: startDate, to: today).day ?? 0, 0)
        return dayOffset / 7
    }

    private func currentProgramWeekRange(
        for program: Program,
        referenceDate: Date,
        calendar: Calendar
    ) -> DateInterval {
        let weekOffset = currentProgramWeekOffset(for: program, referenceDate: referenceDate, calendar: calendar)
        let weekStart = calendar.date(
            byAdding: .day,
            value: weekOffset * 7,
            to: calendar.startOfDay(for: program.startDate)
        ) ?? calendar.startOfDay(for: program.startDate)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        return DateInterval(start: weekStart, end: weekEnd)
    }

    private func orderedWeeklyWorkouts(for block: ProgramBlock?) -> [ProgramWorkout] {
        guard let block else { return [] }
        return block.workouts.sorted { lhs, rhs in
            let leftDay = lhs.weekdayIndex ?? Int.max
            let rightDay = rhs.weekdayIndex ?? Int.max
            if leftDay == rightDay {
                if lhs.order == rhs.order {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.order < rhs.order
            }
            return leftDay < rightDay
        }
    }

    private func nextWorkoutAfter(_ workout: ProgramWorkout, in orderedWorkouts: [ProgramWorkout]) -> ProgramWorkout? {
        guard let currentIndex = orderedWorkouts.firstIndex(where: { $0.id == workout.id }) else {
            return nil
        }
        let nextIndex = orderedWorkouts.index(after: currentIndex)
        guard orderedWorkouts.indices.contains(nextIndex) else { return nil }
        return orderedWorkouts[nextIndex]
    }

    private func continuousConsumedWorkoutCount(
        in targetBlock: ProgramBlock,
        for program: Program,
        blocks: [ProgramBlock],
        completedSessions: [Session]
    ) -> Int {
        var remainingConsumedCount = max(program.continuousSkippedWorkoutCount, 0) + completedSessions.count

        for block in blocks {
            let workoutsCount = max(block.workouts.count, 1)
            let blockCapacity = block.repeatsForever ? Int.max : max(block.durationCount, 1) * workoutsCount
            if block.id == targetBlock.id {
                return remainingConsumedCount
            }
            if block.repeatsForever {
                return 0
            }
            remainingConsumedCount = max(remainingConsumedCount - blockCapacity, 0)
        }

        return 0
    }

    private func weeklyDueSummary(
        for program: Program,
        state: ProgramResolvedState,
        sessions: [Session],
        referenceDate: Date,
        calendar: Calendar
    ) -> String {
        if let nextWorkout = state.nextWorkout,
           let weekdayIndex = nextWorkout.weekdayIndex {
            let dueDate = nextDate(
                for: weekdayIndex,
                from: referenceDate,
                allowToday: state.shouldShowDashboardStartAction,
                calendar: calendar
            )
            return formattedDueDate(dueDate, referenceDate: referenceDate, calendar: calendar)
        }

        let nextWeekReference = currentProgramWeekRange(
            for: program,
            referenceDate: referenceDate,
            calendar: calendar
        ).end
        let nextState = resolvedState(
            for: program,
            sessions: sessions,
            referenceDate: nextWeekReference,
            calendar: calendar
        )

        if let nextWorkout = nextState.nextWorkout,
           let weekdayIndex = nextWorkout.weekdayIndex {
            let dueDate = nextDate(
                for: weekdayIndex,
                from: nextWeekReference,
                allowToday: true,
                calendar: calendar
            )
            return formattedDueDate(dueDate, referenceDate: referenceDate, calendar: calendar)
        }

        return "TBD"
    }

    private func continuousDueSummary(
        for program: Program,
        state: ProgramResolvedState,
        sessions: [Session],
        referenceDate: Date,
        calendar: Calendar
    ) -> String {
        let startOfReference = calendar.startOfDay(for: referenceDate)

        guard let recentCompletedSession = state.recentCompletedSession else {
            return formattedDueDate(startOfReference, referenceDate: referenceDate, calendar: calendar)
        }

        let completedCount = completedSessions(for: program, sessions: sessions).count
        let nextDueDate = nextContinuousWorkoutDate(
            for: program,
            completedWorkoutCount: completedCount,
            recentCompletedAt: recentCompletedSession.timestampDone,
            referenceDate: referenceDate,
            calendar: calendar
        )

        return formattedDueDate(nextDueDate, referenceDate: referenceDate, calendar: calendar)
    }

    private func nextContinuousWorkoutDate(
        for program: Program,
        completedWorkoutCount: Int,
        recentCompletedAt: Date,
        referenceDate: Date,
        calendar: Calendar
    ) -> Date {
        let startOfReference = calendar.startOfDay(for: referenceDate)
        let lastCompletedDay = calendar.startOfDay(for: recentCompletedAt)
        let trainingDays = max(program.trainDaysBeforeRest, 1)
        let restDays = max(program.restDays, 0)
        let consumedWorkoutCount = max(program.continuousSkippedWorkoutCount, 0) + completedWorkoutCount

        let offsetAfterCompletion: Int
        if restDays == 0 {
            offsetAfterCompletion = 1
        } else if consumedWorkoutCount > 0, consumedWorkoutCount % trainingDays == 0 {
            offsetAfterCompletion = restDays + 1
        } else {
            offsetAfterCompletion = 1
        }

        let scheduledDate = calendar.date(
            byAdding: .day,
            value: offsetAfterCompletion,
            to: lastCompletedDay
        ) ?? startOfReference

        return scheduledDate > startOfReference ? scheduledDate : startOfReference
    }

    private func nextDate(
        for weekdayIndex: Int,
        from referenceDate: Date,
        allowToday: Bool,
        calendar: Calendar
    ) -> Date {
        let startOfDay = calendar.startOfDay(for: referenceDate)
        let todayIndex = ProgramWeekday.mondayBasedIndex(for: startOfDay, calendar: calendar)
        var delta = weekdayIndex - todayIndex
        if delta < 0 || (!allowToday && delta == 0) {
            delta += 7
        }
        return calendar.date(byAdding: .day, value: delta, to: startOfDay) ?? startOfDay
    }

    private func formattedDueDate(
        _ dueDate: Date,
        referenceDate: Date,
        calendar: Calendar
    ) -> String {
        let startOfReference = calendar.startOfDay(for: referenceDate)
        let startOfDueDate = calendar.startOfDay(for: dueDate)

        if calendar.isDate(startOfDueDate, inSameDayAs: startOfReference) {
            return "Today"
        }

        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfReference),
           calendar.isDate(startOfDueDate, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }

        if let nextWeek = calendar.date(byAdding: .day, value: 7, to: startOfReference),
           startOfDueDate < nextWeek,
           let weekday = ProgramWeekday(rawValue: ProgramWeekday.mondayBasedIndex(for: startOfDueDate, calendar: calendar)) {
            return weekday.title
        }

        return startOfDueDate.formatted(date: .abbreviated, time: .omitted)
    }

    @discardableResult
    private func sanitizeSkipState(
        for program: Program,
        referenceDate: Date,
        calendar: Calendar
    ) -> Bool {
        var didMutate = false

        if program.continuousSkippedWorkoutCount < 0 {
            program.continuousSkippedWorkoutCount = 0
            didMutate = true
        }

        if program.mode == .weekly {
            let currentWeekOffset = currentProgramWeekOffset(for: program, referenceDate: referenceDate, calendar: calendar)
            if let storedWeekOffset = program.weeklySkipWeekOffset,
               storedWeekOffset != currentWeekOffset {
                program.weeklySkipWeekOffset = nil
                program.weeklySkipNextWorkoutId = nil
                didMutate = true
            } else if let workoutId = program.weeklySkipNextWorkoutId {
                let currentBlock = currentWeeklyBlock(
                    for: program,
                    blocks: sortedBlocks(for: program),
                    referenceDate: referenceDate,
                    calendar: calendar
                )
                let isValid = orderedWeeklyWorkouts(for: currentBlock).contains(where: { $0.id == workoutId })
                if !isValid {
                    program.weeklySkipWeekOffset = nil
                    program.weeklySkipNextWorkoutId = nil
                    didMutate = true
                }
            }
        } else if program.weeklySkipWeekOffset != nil || program.weeklySkipNextWorkoutId != nil {
            program.weeklySkipWeekOffset = nil
            program.weeklySkipNextWorkoutId = nil
            didMutate = true
        }

        return didMutate
    }

    private func persistCursorChanges(for program: Program) {
        do {
            try repository.saveChanges(for: program)
        } catch {
            print("Failed to persist program cursor changes: \(error)")
        }
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

    func isWorkoutStartable(_ workout: ProgramWorkout) -> Bool {
        routineForWorkout(workout) != nil
    }

    private func routineForWorkout(_ workout: ProgramWorkout) -> Routine? {
        if let routineId = workout.routineIdSnapshot {
            let descriptor = FetchDescriptor<Routine>(
                predicate: #Predicate<Routine> { routine in
                    routine.id == routineId && routine.soft_deleted == false && routine.isArchived == false
                }
            )
            return try? modelContext.fetch(descriptor).first
        }

        let trimmedName = workout.routineNameSnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName != "Routine" else { return nil }
        let userId = workout.programBlock.program.user_id
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate<Routine> { routine in
                routine.user_id == userId &&
                routine.name == trimmedName &&
                routine.soft_deleted == false &&
                routine.isArchived == false
            }
        )
        return try? modelContext.fetch(descriptor).first
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
        guard let block else { return noBlockLabel }
        if block.isHiddenRepeatingBlock {
            return workoutRotationLabel
        }
        return block.displayName
    }

    private var addWorkoutLabel: String {
        String(localized: LocalizedStringResource(
            "programmes.action.addWorkout",
            defaultValue: "Add Workout",
            table: "Programmes"
        ))
    }

    private var addWorkoutsToBeginLabel: String {
        String(localized: LocalizedStringResource(
            "programmes.state.addWorkoutsToBegin",
            defaultValue: "Add workouts to begin",
            table: "Programmes"
        ))
    }

    private var allWorkoutsCompletedThisWeekLabel: String {
        String(localized: LocalizedStringResource(
            "programmes.state.allWorkoutsCompletedThisWeek",
            defaultValue: "All workouts completed this week",
            table: "Programmes"
        ))
    }

    private var completedLabel: String {
        String(localized: LocalizedStringResource(
            "programmes.state.completed",
            defaultValue: "Completed",
            table: "Programmes"
        ))
    }

    private var noBlockLabel: String {
        String(localized: LocalizedStringResource(
            "programmes.state.noBlock",
            defaultValue: "No block",
            table: "Programmes"
        ))
    }

    private var noWorkoutLabel: String {
        String(localized: LocalizedStringResource(
            "programmes.state.noWorkout",
            defaultValue: "No workout",
            table: "Programmes"
        ))
    }

    private var noWorkoutsYetLabel: String {
        String(localized: LocalizedStringResource(
            "programmes.state.noWorkoutsYet",
            defaultValue: "No workouts yet",
            table: "Programmes"
        ))
    }

    private var resumeCurrentWorkoutLabel: String {
        String(localized: LocalizedStringResource(
            "programmes.action.resumeCurrentWorkout",
            defaultValue: "Resume Current Workout",
            table: "Programmes"
        ))
    }

    private var startNextWorkoutLabel: String {
        String(localized: LocalizedStringResource(
            "programmes.action.startNextWorkout",
            defaultValue: "Start Next Workout",
            table: "Programmes"
        ))
    }

    private var workoutCompleteLabel: String {
        String(localized: LocalizedStringResource(
            "programmes.action.workoutComplete",
            defaultValue: "Workout Complete",
            table: "Programmes"
        ))
    }

    private var workoutRotationLabel: String {
        String(localized: LocalizedStringResource(
            "programmes.state.workoutRotation",
            defaultValue: "Workout Rotation",
            table: "Programmes"
        ))
    }
}

enum ProgramWorkoutMoveDirection {
    case up
    case down
}
