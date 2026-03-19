import Foundation
import SwiftData
import Combine
import SwiftUI

final class ProgramService: ServiceBase, ObservableObject {
    struct ProgressionSummary {
        let readyToIncrease: Int
        let inProgress: Int
        let recentlyAdvanced: Int

        static let empty = ProgressionSummary(
            readyToIncrease: 0,
            inProgress: 0,
            recentlyAdvanced: 0
        )

        var hasContent: Bool {
            readyToIncrease > 0 || inProgress > 0 || recentlyAdvanced > 0
        }
    }

    @Published var programs: [Program] = []
    @Published var archivedPrograms: [Program] = []
    @Published var progressionSummary: ProgressionSummary = .empty

    override func loadFeature() {
        loadPrograms()
        loadArchivedPrograms()
        loadProgressionSummary()
    }

    func loadPrograms() {
        guard let userId = currentUser?.id else {
            programs = []
            return
        }

        let descriptor = FetchDescriptor<Program>(
            predicate: #Predicate<Program> { program in
                program.user_id == userId && program.isArchived == false
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        do {
            programs = try modelContext.fetch(descriptor)
        } catch {
            programs = []
        }
    }

    func loadArchivedPrograms() {
        guard let userId = currentUser?.id else {
            archivedPrograms = []
            return
        }

        let descriptor = FetchDescriptor<Program>(
            predicate: #Predicate<Program> { program in
                program.user_id == userId && program.isArchived == true
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        do {
            archivedPrograms = try modelContext.fetch(descriptor)
        } catch {
            archivedPrograms = []
        }
    }

    @discardableResult
    func addProgram(
        name: String,
        notes: String = "",
        isActive: Bool = false,
        isCurrent: Bool = false,
        isBuiltIn: Bool = false,
        builtInKey: String? = nil,
        startDate: Date? = nil
    ) -> Program? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        guard let userId = currentUser?.id else { return nil }

        let created = Program(
            user_id: userId,
            name: trimmedName,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            isArchived: false,
            isActive: isActive,
            isCurrent: isCurrent,
            isBuiltIn: isBuiltIn,
            builtInKey: builtInKey,
            startDate: startDate
        )
        modelContext.insert(created)
        createInitialBlockIfNeeded(for: created, userId: userId)

        do {
            if isCurrent {
                enforceSingleCurrentProgram(for: userId, keep: created)
            }
            try modelContext.save()
            _ = materializeTemplateSchedule(for: created)
            if isCurrent || isActive {
                ensureMaterializationHorizonIfNeededForMutation(for: created)
            }
            loadPrograms()
            loadArchivedPrograms()
            return created
        } catch {
            return nil
        }
    }

    @discardableResult
    func updateProgram(
        _ program: Program,
        name: String,
        notes: String,
        isActive: Bool,
        startDate: Date?,
        isCurrent: Bool,
        lengthMode: ProgramLengthMode
    ) -> Bool {
        guard !program.isBuiltIn else { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }

        program.name = trimmedName
        program.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        program.isActive = isActive
        program.startDate = startDate
        program.isCurrent = isCurrent
        program.resolvedProgramLengthMode = lengthMode

        do {
            if isCurrent {
                enforceSingleCurrentProgram(for: program.user_id, keep: program)
            }
            try modelContext.save()
            if isCurrent || isActive {
                ensureMaterializationHorizonIfNeededForMutation(for: program)
            }
            loadPrograms()
            loadArchivedPrograms()
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func archiveProgram(_ program: Program) -> Bool {
        guard !program.isBuiltIn else { return false }
        program.isArchived = true
        program.isActive = false
        program.isCurrent = false
        do {
            try modelContext.save()
            loadPrograms()
            loadArchivedPrograms()
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func restoreProgram(_ program: Program) -> Bool {
        program.isArchived = false
        do {
            try modelContext.save()
            loadPrograms()
            loadArchivedPrograms()
            return true
        } catch {
            return false
        }
    }

    func canDeleteProgramPermanently(_ program: Program) -> Bool {
        if program.isBuiltIn { return false }
        if !program.sessions.isEmpty { return false }
        if program.programDays.contains(where: { !$0.sessions.isEmpty }) { return false }
        return true
    }

    @discardableResult
    func deleteProgramPermanentlyIfSafe(_ program: Program) -> Bool {
        guard canDeleteProgramPermanently(program) else { return false }
        modelContext.delete(program)
        do {
            try modelContext.save()
            loadPrograms()
            loadArchivedPrograms()
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func addProgramDay(
        to program: Program,
        title: String,
        weekIndex: Int,
        dayIndex: Int,
        blockIndex: Int?,
        routine: Routine?
    ) -> ProgramDay? {
        guard !program.isBuiltIn else { return nil }
        guard let userId = currentUser?.id else { return nil }
        guard program.user_id == userId else { return nil }
        guard isValidRoutineForProgramOwner(routine, ownerId: userId) else { return nil }

        let nextOrder = (program.programDays.map(\.order).max() ?? -1) + 1
        let created = ProgramDay(
            user_id: userId,
            program: program,
            routine: routine,
            weekIndex: max(0, weekIndex),
            dayIndex: max(0, dayIndex),
            blockIndex: blockIndex,
            title: storedWorkoutTitle(from: title, routine: routine),
            order: nextOrder
        )
        modelContext.insert(created)
        program.programDays.append(created)

        do {
            try modelContext.save()
            loadPrograms()
            return created
        } catch {
            return nil
        }
    }

    @discardableResult
    func updateProgramDay(
        _ programDay: ProgramDay,
        title: String,
        weekIndex: Int,
        dayIndex: Int,
        blockIndex: Int?,
        order: Int,
        routine: Routine?
    ) -> Bool {
        guard programDay.program?.isBuiltIn != true else { return false }
        guard let userId = currentUser?.id else { return false }
        guard programDay.user_id == userId else { return false }
        guard isValidRoutineForProgramOwner(routine, ownerId: userId) else { return false }

        programDay.title = storedWorkoutTitle(from: title, routine: routine)
        programDay.weekIndex = max(0, weekIndex)
        programDay.dayIndex = max(0, dayIndex)
        programDay.blockIndex = blockIndex
        programDay.order = max(0, order)
        programDay.routine = routine

        do {
            try modelContext.save()
            loadPrograms()
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func removeProgramDay(_ programDay: ProgramDay) -> Bool {
        guard programDay.program?.isBuiltIn != true else { return false }
        // Keep historical links intact by preventing removal once any session references this day.
        guard programDay.sessions.isEmpty else { return false }

        modelContext.delete(programDay)
        do {
            try modelContext.save()
            loadPrograms()
            return true
        } catch {
            return false
        }
    }

    func moveProgramDays(in program: Program, from source: IndexSet, to destination: Int) {
        guard !program.isBuiltIn else { return }
        var days = program.programDays.sorted { $0.order < $1.order }
        days.move(fromOffsets: source, toOffset: destination)
        for (index, day) in days.enumerated() {
            day.order = index
        }
        try? modelContext.save()
        loadPrograms()
    }

    @discardableResult
    func addOverride(
        to programDay: ProgramDay,
        exercise: Exercise? = nil,
        progression: ProgressionProfile? = nil,
        setsTarget: Int? = nil,
        repsTarget: Int? = nil,
        repsLow: Int? = nil,
        repsHigh: Int? = nil,
        notes: String = ""
    ) -> ProgramDayExerciseOverride? {
        guard programDay.program?.isBuiltIn != true else { return nil }
        guard let userId = currentUser?.id else { return nil }

        let nextOrder = (programDay.exerciseOverrides.map(\.order).max() ?? -1) + 1
        let created = ProgramDayExerciseOverride(
            user_id: userId,
            programDay: programDay,
            exercise: exercise,
            progression: progression,
            setsTarget: setsTarget,
            repsTarget: repsTarget,
            repsLow: repsLow,
            repsHigh: repsHigh,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            order: nextOrder
        )
        modelContext.insert(created)
        programDay.exerciseOverrides.append(created)

        do {
            try modelContext.save()
            return created
        } catch {
            return nil
        }
    }

    @discardableResult
    func updateOverride(
        _ overrideModel: ProgramDayExerciseOverride,
        exercise: Exercise?,
        progression: ProgressionProfile?,
        setsTarget: Int?,
        repsTarget: Int?,
        repsLow: Int?,
        repsHigh: Int?,
        notes: String,
        order: Int
    ) -> Bool {
        guard overrideModel.programDay.program?.isBuiltIn != true else { return false }
        overrideModel.exercise = exercise
        overrideModel.progression = progression
        overrideModel.setsTarget = setsTarget
        overrideModel.repsTarget = repsTarget
        overrideModel.repsLow = repsLow
        overrideModel.repsHigh = repsHigh
        overrideModel.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        overrideModel.order = max(0, order)

        do {
            try modelContext.save()
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func removeOverride(_ overrideModel: ProgramDayExerciseOverride) -> Bool {
        guard overrideModel.programDay.program?.isBuiltIn != true else { return false }
        modelContext.delete(overrideModel)
        do {
            try modelContext.save()
            return true
        } catch {
            return false
        }
    }

    func moveOverrides(in programDay: ProgramDay, from source: IndexSet, to destination: Int) {
        guard programDay.program?.isBuiltIn != true else { return }
        var overrides = programDay.exerciseOverrides.sorted { $0.order < $1.order }
        overrides.move(fromOffsets: source, toOffset: destination)
        for (index, overrideModel) in overrides.enumerated() {
            overrideModel.order = index
        }
        try? modelContext.save()
    }

    func activeRoutines() -> [Routine] {
        guard let userId = currentUser?.id else { return [] }
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate<Routine> { routine in
                routine.user_id == userId && routine.isArchived == false
            },
            sortBy: [SortDescriptor(\.order)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func activeExercises() -> [Exercise] {
        guard let userId = currentUser?.id else { return [] }
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { exercise in
                exercise.user_id == userId && exercise.isArchived == false
            },
            sortBy: [SortDescriptor(\.name)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func availableProgressionProfiles() -> [ProgressionProfile] {
        guard let userId = currentUser?.id else { return [] }
        let descriptor = FetchDescriptor<ProgressionProfile>(
            predicate: #Predicate<ProgressionProfile> { profile in
                profile.isArchived == false && (profile.user_id == userId || profile.user_id == nil)
            },
            sortBy: [SortDescriptor(\.name)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func loadProgressionSummary() {
        guard let userId = currentUser?.id else {
            progressionSummary = .empty
            return
        }

        let descriptor = FetchDescriptor<ProgressionState>(
            predicate: #Predicate<ProgressionState> { state in
                state.user_id == userId
            }
        )

        do {
            let states = try modelContext.fetch(descriptor)
            let now = Date()
            let recentWindow: TimeInterval = 14 * 24 * 60 * 60

            var readyToIncrease = 0
            var inProgress = 0
            var recentlyAdvanced = 0

            for state in states {
                guard let progression = state.progression else { continue }
                let requiredSuccesses = max(progression.requiredSuccessSessions, 1)

                if state.successCount >= requiredSuccesses {
                    readyToIncrease += 1
                } else if state.successCount > 0 {
                    inProgress += 1
                }

                if let lastAdvancedAt = state.lastAdvancedAt,
                   now.timeIntervalSince(lastAdvancedAt) <= recentWindow {
                    recentlyAdvanced += 1
                }
            }

            progressionSummary = ProgressionSummary(
                readyToIncrease: readyToIncrease,
                inProgress: inProgress,
                recentlyAdvanced: recentlyAdvanced
            )
        } catch {
            progressionSummary = .empty
        }
    }

    func statusText(for program: Program) -> String {
        if program.isBuiltIn {
            return "Built-In"
        }
        if program.isActive {
            return "Active"
        }

        return "Program"
    }

    @discardableResult
    func duplicateProgramForEditing(_ program: Program) -> Program? {
        guard let userId = currentUser?.id else { return nil }

        let duplicate = Program(
            user_id: userId,
            name: "\(program.name) Copy",
            notes: program.notes,
            isArchived: false,
            isActive: false,
            isCurrent: false,
            isBuiltIn: false,
            builtInKey: nil,
            lengthMode: program.resolvedProgramLengthMode,
            startDate: program.startDate,
            currentWeekOverride: nil
        )
        modelContext.insert(duplicate)

        let sortedDays = program.programDays.sorted { $0.order < $1.order }
        for day in sortedDays {
            let duplicatedDay = ProgramDay(
                user_id: userId,
                program: duplicate,
                routine: day.routine,
                weekIndex: day.weekIndex,
                dayIndex: day.dayIndex,
                blockIndex: day.blockIndex,
                title: day.title,
                order: day.order
            )
            modelContext.insert(duplicatedDay)
            duplicate.programDays.append(duplicatedDay)

            let sortedOverrides = day.exerciseOverrides.sorted { $0.order < $1.order }
            for override in sortedOverrides {
                let duplicatedOverride = ProgramDayExerciseOverride(
                    user_id: userId,
                    programDay: duplicatedDay,
                    exercise: override.exercise,
                    progression: override.progression,
                    setsTarget: override.setsTarget,
                    repsTarget: override.repsTarget,
                    repsLow: override.repsLow,
                    repsHigh: override.repsHigh,
                    notes: override.notes,
                    order: override.order
                )
                modelContext.insert(duplicatedOverride)
                duplicatedDay.exerciseOverrides.append(duplicatedOverride)
            }
        }

        do {
            try modelContext.save()
            loadPrograms()
            return duplicate
        } catch {
            return nil
        }
    }

    func currentProgram() -> Program? {
        guard let userId = currentUser?.id else { return nil }
        return programs.first(where: { $0.user_id == userId && $0.isCurrent })
    }

    @discardableResult
    func setCurrentProgram(_ program: Program?) -> Bool {
        guard let userId = currentUser?.id else { return false }
        for item in programs where item.user_id == userId {
            item.isCurrent = item.id == program?.id
        }
        if let program {
            initializeProgramStateIfNeeded(for: program)
        }
        do {
            try modelContext.save()
            if let program {
                ensureMaterializationHorizonIfNeededForMutation(for: program)
            }
            loadPrograms()
            return true
        } catch {
            return false
        }
    }

    func computedCurrentWeek(for program: Program, now: Date = Date()) -> Int {
        guard let startDate = program.startDate else { return 0 }
        let calendar = Calendar.current
        let startWeek = calendar.dateInterval(of: .weekOfYear, for: startDate)?.start ?? startDate
        let nowWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let components = calendar.dateComponents([.weekOfYear], from: startWeek, to: nowWeek)
        return max(0, components.weekOfYear ?? 0)
    }

    func effectiveCurrentWeek(for program: Program, now: Date = Date()) -> Int {
        if let override = program.currentWeekOverride {
            return max(0, override)
        }
        return computedCurrentWeek(for: program, now: now)
    }

    @discardableResult
    func setManualCurrentWeek(_ week: Int?, for program: Program) -> Bool {
        guard !program.isBuiltIn else { return false }
        program.currentWeekOverride = week.map { max(0, $0) }
        do {
            try modelContext.save()
            loadPrograms()
            return true
        } catch {
            return false
        }
    }

    func currentBlock(for program: Program) -> ProgramBlock? {
        let week = effectiveCurrentWeek(for: program)
        return resolvedBlock(for: program, weekIndex: week)
    }

    func nextScheduledDay(for program: Program) -> ProgramDay? {
        if let stateResolved = nextScheduledDayFromProgramState(for: program) {
            return stateResolved
        }

        let sorted = sortedEligibleProgramDays(for: program)
        guard !sorted.isEmpty else { return nil }

        let currentWeek = effectiveCurrentWeek(for: program)
        let todayWeekdayIndex = Calendar.current.component(.weekday, from: Date()) - 1

        guard let block = resolvedBlock(for: program, weekIndex: currentWeek) else {
            return sorted.first
        }

        switch block.resolvedScheduleMode {
        case .calendar:
            return calendarNextDay(
                sorted: sorted,
                currentWeek: currentWeek,
                todayWeekdayIndex: todayWeekdayIndex
            )
        case .rotation:
            return rotationNextDay(
                sorted: sorted,
                program: program,
                currentWeek: currentWeek,
                todayWeekdayIndex: todayWeekdayIndex
            )
        }
    }

    func programProgress(for program: Program) -> (completed: Int, total: Int) {
        let total = program.programDays.count
        guard total > 0 else { return (0, 0) }
        let completed = completedProgramDayIds(for: program).count
        return (min(completed, total), total)
    }

    func blockProgress(for program: Program, block: ProgramBlock) -> (completed: Int, total: Int) {
        let blockDays = program.programDays.filter { day in
            day.weekIndex >= block.startWeekIndex && day.weekIndex <= block.endWeekIndex
        }
        let total = blockDays.count
        guard total > 0 else { return (0, 0) }
        let blockDayIds = Set(blockDays.map(\.id))
        let completed = completedProgramDayIds(for: program).intersection(blockDayIds).count
        return (min(completed, total), total)
    }

    func nextScheduledDayText(for program: Program) -> String? {
        guard let day = nextScheduledDay(for: program) else { return nil }
        let weekdayLabel = weekdayLabel(for: day.dayIndex)
        let routineName = day.routine?.name ?? "No routine"
        return "\(weekdayLabel) · Week \(day.weekIndex + 1) · \(routineName)"
    }

    func currentBlockProgressText(for program: Program) -> String? {
        let blocks = sortedNonArchivedBlocks(for: program)
        guard !blocks.isEmpty else { return nil }
        let blockIndex = min(max(program.currentBlockIndex ?? 0, 0), blocks.count - 1)
        return "Block \(blockIndex + 1) of \(blocks.count)"
    }

    func currentWorkoutProgressText(for program: Program) -> String? {
        guard let block = currentStateBlock(for: program) else { return nil }
        let workouts = blockWorkouts(for: program, block: block)
        guard !workouts.isEmpty else { return nil }
        let workoutIndex = min(max(program.currentWorkoutIndex ?? 0, 0), workouts.count - 1)
        return "Workout \(workoutIndex + 1) of \(workouts.count)"
    }

    @discardableResult
    func prepareScheduleForSessionStart(for program: Program) -> ProgramDay? {
        let didInitializeState = initializeProgramStateIfNeeded(for: program)
        let didMaterialize = ensureMaterializationHorizonIfNeededForMutation(for: program)
        if didInitializeState {
            guard persistProgramMutationsAndRefresh() else { return nil }
        } else if didMaterialize {
            refreshProgramCollections()
        }
        let resolvedProgram = programById(program.id) ?? program
        return nextScheduledDay(for: resolvedProgram)
    }

    private func sortedEligibleProgramDays(for program: Program) -> [ProgramDay] {
        program.programDays
            .filter { $0.routine != nil }
            .sorted(by: { lhs, rhs in
                if lhs.weekIndex != rhs.weekIndex { return lhs.weekIndex < rhs.weekIndex }
                if lhs.dayIndex != rhs.dayIndex { return lhs.dayIndex < rhs.dayIndex }
                return lhs.order < rhs.order
            })
    }

    private func calendarNextDay(
        sorted: [ProgramDay],
        currentWeek: Int,
        todayWeekdayIndex: Int
    ) -> ProgramDay? {
        if let currentWeekCandidate = sorted.first(where: { day in
            day.weekIndex == currentWeek && day.dayIndex >= todayWeekdayIndex
        }) {
            return currentWeekCandidate
        }
        return sorted.first(where: { $0.weekIndex > currentWeek }) ?? sorted.first
    }

    private func rotationNextDay(
        sorted: [ProgramDay],
        program: Program,
        currentWeek: Int,
        todayWeekdayIndex: Int
    ) -> ProgramDay? {
        if let nextAfterLatest = nextDayAfterLatestCompleted(sorted: sorted, program: program) {
            return nextAfterLatest
        }

        if let inCurrentWeek = sorted.first(where: { day in
            day.weekIndex == currentWeek && day.dayIndex >= todayWeekdayIndex
        }) {
            return inCurrentWeek
        }

        return sorted.first(where: { $0.weekIndex > currentWeek }) ?? sorted.first
    }

    private func nextDayAfterLatestCompleted(sorted: [ProgramDay], program: Program) -> ProgramDay? {
        guard let latestProgramSession = latestProgramSession(for: program),
            let latestProgramDay = latestProgramSession.programDay,
            let latestIndex = sorted.firstIndex(where: { $0.id == latestProgramDay.id }) else {
            return nil
        }

        let nextIndex = sorted.index(after: latestIndex)
        if nextIndex < sorted.endIndex {
            return sorted[nextIndex]
        }
        return sorted.first
    }

    private func completedProgramDayIds(for program: Program) -> Set<UUID> {
        Set(program.sessions.compactMap { $0.programDay?.id })
    }

    private func latestProgramSession(for program: Program) -> Session? {
        program.sessions
            .filter { $0.programDay != nil }
            .sorted { $0.timestamp > $1.timestamp }
            .first
    }

    private var continuousWeeksAheadDefault: Int { 12 }

    @discardableResult
    func skipCurrentWorkout(for program: Program) -> Bool {
        let didInitializeState = initializeProgramStateIfNeeded(for: program)
        let didAdvance = advanceProgramState(
            for: program,
            completedProgramDayId: nil,
            updateCompletionReference: false
        )
        if didAdvance {
            refreshProgramCollections()
            return true
        }
        if didInitializeState {
            return persistProgramMutationsAndRefresh()
        }
        return false
    }

    @discardableResult
    func postponeCurrentWorkout(for program: Program) -> Bool {
        _ = initializeProgramStateIfNeeded(for: program)
        program.lastProgressedAt = Date()
        return persistProgramMutationsAndRefresh()
    }

    @discardableResult
    func restartProgramState(for program: Program) -> Bool {
        let blocks = sortedNonArchivedBlocks(for: program)
        guard !blocks.isEmpty else { return false }
        program.currentBlockIndex = 0
        program.currentWorkoutIndex = 0
        program.lastCompletedProgramDayId = nil
        program.lastProgressedAt = Date()
        if program.startedAt == nil {
            program.startedAt = Date()
        }
        do {
            try modelContext.save()
            loadPrograms()
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func advanceProgramStateIfNeeded(afterCompleting session: Session) -> Bool {
        guard let program = session.program, let completedDay = session.programDay else { return false }
        guard program.user_id == session.user_id else { return false }
        initializeProgramStateIfNeeded(for: program)
        if !hasProgramState(program) {
            alignStateWithProgramDay(program: program, day: completedDay)
        }
        let currentPlannedDay = nextScheduledDayFromProgramState(for: program)
        if currentPlannedDay?.id != completedDay.id {
            // If state was already advanced when starting this session, only update completion metadata.
            program.lastCompletedProgramDayId = completedDay.id
            program.lastProgressedAt = Date()
            return persistProgramMutationsAndRefresh()
        }
        let didAdvance = advanceProgramState(
            for: program,
            completedProgramDayId: completedDay.id,
            updateCompletionReference: true
        )
        if didAdvance { refreshProgramCollections() }
        return didAdvance
    }

    @discardableResult
    func advanceProgramStateAfterStartingSession(for program: Program, startedProgramDay: ProgramDay) -> Bool {
        guard let userId = currentUser?.id else { return false }
        guard program.user_id == userId else { return false }
        guard startedProgramDay.user_id == userId else { return false }

        initializeProgramStateIfNeeded(for: program)

        if !hasProgramState(program) {
            alignStateWithProgramDay(program: program, day: startedProgramDay)
        } else if let currentPlannedDay = nextScheduledDayFromProgramState(for: program),
                  currentPlannedDay.id != startedProgramDay.id {
            alignStateWithProgramDay(program: program, day: startedProgramDay)
        }

        let didAdvance = advanceProgramState(
            for: program,
            completedProgramDayId: nil,
            updateCompletionReference: false
        )
        if didAdvance { refreshProgramCollections() }
        return didAdvance
    }

    @discardableResult
    private func initializeProgramStateIfNeeded(for program: Program) -> Bool {
        let blocks = sortedNonArchivedBlocks(for: program)
        guard !blocks.isEmpty else { return false }
        guard !hasProgramState(program) else { return false }

        program.currentBlockIndex = 0
        program.currentWorkoutIndex = 0
        program.lastCompletedProgramDayId = nil
        program.lastProgressedAt = Date()
        if program.startedAt == nil {
            program.startedAt = Date()
        }
        return true
    }

    private func hasProgramState(_ program: Program) -> Bool {
        program.currentBlockIndex != nil && program.currentWorkoutIndex != nil
    }

    private func nextScheduledDayFromProgramState(for program: Program) -> ProgramDay? {
        guard hasProgramState(program) else { return nil }
        ensureMaterializationHorizonIfNeededForMutation(for: program)
        guard let block = currentStateBlock(for: program) else { return nil }
        let workouts = blockWorkouts(for: program, block: block)
        guard !workouts.isEmpty else { return nil }
        let workoutIndex = max(program.currentWorkoutIndex ?? 0, 0)
        let clampedIndex = min(workoutIndex, workouts.count - 1)
        return workouts[clampedIndex]
    }

    private func currentStateBlock(for program: Program) -> ProgramBlock? {
        let blocks = sortedNonArchivedBlocks(for: program)
        guard !blocks.isEmpty else { return nil }
        let index = min(max(program.currentBlockIndex ?? 0, 0), blocks.count - 1)
        return blocks[index]
    }

    private func alignStateWithProgramDay(program: Program, day: ProgramDay) {
        let blocks = sortedNonArchivedBlocks(for: program)
        guard !blocks.isEmpty else { return }
        guard let blockIndex = blockIndex(for: day, in: program, blocks: blocks) else { return }
        let block = blocks[blockIndex]
        let workouts = blockWorkouts(for: program, block: block)
        let workoutIndex = workouts.firstIndex(where: { $0.id == day.id }) ?? 0
        program.currentBlockIndex = blockIndex
        program.currentWorkoutIndex = workoutIndex
    }

    private func advanceProgramState(
        for program: Program,
        completedProgramDayId: UUID?,
        updateCompletionReference: Bool
    ) -> Bool {
        let blocks = sortedNonArchivedBlocks(for: program)
        guard !blocks.isEmpty else { return false }
        var blockIndex = min(max(program.currentBlockIndex ?? 0, 0), blocks.count - 1)
        let currentBlock = blocks[blockIndex]
        let workouts = blockWorkouts(for: program, block: currentBlock)
        guard !workouts.isEmpty else { return false }

        var workoutIndex = max(program.currentWorkoutIndex ?? 0, 0)
        workoutIndex += 1

        if workoutIndex >= workouts.count {
            let nextBlockIndex = blockIndex + 1
            if nextBlockIndex < blocks.count {
                blockIndex = nextBlockIndex
                workoutIndex = 0
            } else if program.resolvedProgramLengthMode == .fixedLength {
                // Phase 14 fixed-length policy: wrap to the first block when finishing the last block.
                blockIndex = 0
                workoutIndex = 0
            } else {
                // Phase 14 continuous policy: stay on last block and continue naturally.
                blockIndex = blocks.count - 1
                ensureMaterializationHorizonIfNeededForMutation(for: program)
                let tailWorkouts = blockWorkouts(for: program, block: blocks[blockIndex])
                if tailWorkouts.isEmpty {
                    workoutIndex = 0
                } else {
                    workoutIndex = min(workoutIndex, tailWorkouts.count - 1)
                }
            }
        }

        program.currentBlockIndex = blockIndex
        program.currentWorkoutIndex = workoutIndex
        if updateCompletionReference {
            program.lastCompletedProgramDayId = completedProgramDayId
        }
        program.lastProgressedAt = Date()

        do {
            try modelContext.save()
            return true
        } catch {
            return false
        }
    }

    private func blockIndex(for day: ProgramDay, in program: Program, blocks: [ProgramBlock]) -> Int? {
        if let sourceBlockId = day.sourceBlock?.id, let idx = blocks.firstIndex(where: { $0.id == sourceBlockId }) {
            return idx
        }
        if let dayBlockIndex = day.blockIndex, let idx = blocks.firstIndex(where: { $0.order == dayBlockIndex }) {
            return idx
        }
        if let idx = blocks.firstIndex(where: { day.weekIndex >= $0.startWeekIndex && day.weekIndex <= $0.endWeekIndex }) {
            return idx
        }
        if program.resolvedProgramLengthMode == .continuous, let last = blocks.indices.last {
            return last
        }
        return nil
    }

    private func blockWorkouts(for program: Program, block: ProgramBlock) -> [ProgramDay] {
        program.programDays
            .filter { $0.routine != nil }
            .filter { day in
                if let sourceBlock = day.sourceBlock, sourceBlock.id == block.id { return true }
                if let dayBlockIndex = day.blockIndex, dayBlockIndex == block.order { return true }
                return day.weekIndex >= block.startWeekIndex && day.weekIndex <= block.endWeekIndex
            }
            .sorted { lhs, rhs in
                if lhs.weekIndex != rhs.weekIndex { return lhs.weekIndex < rhs.weekIndex }
                if lhs.dayIndex != rhs.dayIndex { return lhs.dayIndex < rhs.dayIndex }
                return lhs.order < rhs.order
            }
    }

    @discardableResult
    private func ensureMaterializationHorizonIfNeededForMutation(for program: Program) -> Bool {
        guard program.resolvedProgramLengthMode == .continuous else { return true }
        let currentWeek = effectiveCurrentWeek(for: program)
        let targetWeek = currentWeek + continuousWeeksAheadDefault
        let maxMaterializedWeek = program.programDays.map(\.weekIndex).max() ?? -1
        if maxMaterializedWeek >= targetWeek { return true }
        return materializeTemplateSchedule(
            for: program,
            weekRange: currentWeek...targetWeek,
            pruneStaleGeneratedRows: false
        )
    }

    @discardableResult
    private func persistProgramMutationsAndRefresh() -> Bool {
        do {
            try modelContext.save()
            refreshProgramCollections()
            return true
        } catch {
            return false
        }
    }

    private func refreshProgramCollections() {
        loadPrograms()
        loadArchivedPrograms()
    }

    private func programById(_ id: UUID) -> Program? {
        guard let userId = currentUser?.id else { return nil }
        let descriptor = FetchDescriptor<Program>(
            predicate: #Predicate<Program> { program in
                program.user_id == userId && program.id == id
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    @discardableResult
    func addBlock(
        to program: Program,
        title: String,
        notes: String = "",
        startWeekIndex: Int,
        endWeekIndex: Int,
        scheduleMode: ProgramScheduleMode = .calendar,
        rotationOnDays: Int? = nil,
        rotationOffDays: Int? = nil
    ) -> ProgramBlock? {
        guard !program.isBuiltIn else { return nil }
        guard let userId = currentUser?.id else { return nil }
        let nextOrder = (program.blocks.map(\.order).max() ?? -1) + 1
        let block = ProgramBlock(
            user_id: userId,
            program: program,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            startWeekIndex: max(0, startWeekIndex),
            endWeekIndex: max(startWeekIndex, endWeekIndex),
            order: nextOrder,
            scheduleMode: scheduleMode,
            rotationOnDays: rotationOnDays,
            rotationOffDays: rotationOffDays
        )
        modelContext.insert(block)
        do {
            try modelContext.save()
            _ = materializeTemplateSchedule(for: program)
            loadPrograms()
            return block
        } catch {
            return nil
        }
    }

    @discardableResult
    func updateBlock(
        _ block: ProgramBlock,
        title: String,
        notes: String,
        startWeekIndex: Int,
        endWeekIndex: Int,
        scheduleMode: ProgramScheduleMode,
        rotationOnDays: Int?,
        rotationOffDays: Int?
    ) -> Bool {
        guard block.program?.isBuiltIn != true else { return false }
        block.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        block.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        block.startWeekIndex = max(0, startWeekIndex)
        block.endWeekIndex = max(block.startWeekIndex, endWeekIndex)
        block.resolvedScheduleMode = scheduleMode
        block.rotationOnDays = rotationOnDays
        block.rotationOffDays = rotationOffDays
        do {
            try modelContext.save()
            if let program = block.program {
                _ = materializeTemplateSchedule(for: program)
            }
            loadPrograms()
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func removeBlock(_ block: ProgramBlock) -> Bool {
        guard block.program?.isBuiltIn != true else { return false }
        let parentProgram = block.program
        let generatedRows = block.materializedProgramDays.filter { $0.isGeneratedFromTemplate }
        if generatedRows.contains(where: { !$0.sessions.isEmpty }) { return false }
        for row in generatedRows {
            modelContext.delete(row)
        }
        modelContext.delete(block)
        do {
            try modelContext.save()
            if let parentProgram {
                _ = materializeTemplateSchedule(for: parentProgram)
            }
            loadPrograms()
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func addTemplateDay(
        to block: ProgramBlock,
        title: String,
        weekDayIndex: Int,
        routine: Routine?,
        notes: String = ""
    ) -> ProgramBlockTemplateDay? {
        guard block.program?.isBuiltIn != true else { return nil }
        guard let userId = currentUser?.id else { return nil }
        let nextOrder = (block.templateDays.map(\.order).max() ?? -1) + 1
        let day = ProgramBlockTemplateDay(
            user_id: userId,
            block: block,
            routine: routine,
            title: storedWorkoutTitle(from: title, routine: routine),
            weekDayIndex: max(0, min(6, weekDayIndex)),
            order: nextOrder,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        modelContext.insert(day)
        do {
            try modelContext.save()
            if let program = block.program {
                _ = materializeTemplateSchedule(for: program)
            }
            loadPrograms()
            return day
        } catch {
            return nil
        }
    }

    @discardableResult
    func updateTemplateDay(
        _ templateDay: ProgramBlockTemplateDay,
        title: String,
        weekDayIndex: Int,
        routine: Routine?,
        notes: String
    ) -> Bool {
        guard templateDay.block?.program?.isBuiltIn != true else { return false }
        templateDay.title = storedWorkoutTitle(from: title, routine: routine)
        templateDay.weekDayIndex = max(0, min(6, weekDayIndex))
        templateDay.routine = routine
        templateDay.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try modelContext.save()
            if let program = templateDay.block?.program {
                _ = materializeTemplateSchedule(for: program)
            }
            loadPrograms()
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func removeTemplateDay(_ templateDay: ProgramBlockTemplateDay) -> Bool {
        guard templateDay.block?.program?.isBuiltIn != true else { return false }
        let parentProgram = templateDay.block?.program
        let generatedRows = templateDay.materializedProgramDays.filter { $0.isGeneratedFromTemplate }
        if generatedRows.contains(where: { !$0.sessions.isEmpty }) { return false }
        for row in generatedRows {
            modelContext.delete(row)
        }
        modelContext.delete(templateDay)
        do {
            try modelContext.save()
            if let parentProgram {
                _ = materializeTemplateSchedule(for: parentProgram)
            }
            loadPrograms()
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func materializeTemplateSchedule(
        for program: Program,
        weekRange: ClosedRange<Int>? = nil,
        pruneStaleGeneratedRows: Bool? = nil
    ) -> Bool {
        guard !program.isBuiltIn else { return false }
        var desiredByKey: [String: MaterializedTemplateCandidate] = [:]
        let nonArchivedBlocks = sortedNonArchivedBlocks(for: program)
        if nonArchivedBlocks.isEmpty { return false }

        if program.resolvedProgramLengthMode == .continuous {
            let targetRange: ClosedRange<Int>
            if let weekRange {
                targetRange = weekRange
            } else {
                let currentWeek = effectiveCurrentWeek(for: program)
                targetRange = currentWeek...(currentWeek + continuousWeeksAheadDefault)
            }

            addContinuousCandidates(
                to: &desiredByKey,
                program: program,
                weekRange: targetRange
            )
        } else {
            for block in nonArchivedBlocks {
                guard block.endWeekIndex >= block.startWeekIndex else { continue }
                let effectiveRange = intersectWeekRange(
                    left: block.startWeekIndex...block.endWeekIndex,
                    right: weekRange
                )
                guard let effectiveRange else { continue }

                let templateDays = block.templateDays.sorted { $0.order < $1.order }
                switch block.resolvedScheduleMode {
                case .calendar:
                    for templateDay in templateDays {
                        for week in effectiveRange {
                            let candidate = MaterializedTemplateCandidate(
                                generationKey: generationKey(
                                    programId: program.id,
                                    blockId: block.id,
                                    templateDayId: templateDay.id,
                                    weekIndex: week
                                ),
                                block: block,
                                templateDay: templateDay,
                                routine: templateDay.routine,
                                weekIndex: week,
                                dayIndex: templateDay.weekDayIndex,
                                order: templateDay.order,
                                title: storedWorkoutTitle(from: templateDay.title, routine: templateDay.routine)
                            )
                            if desiredByKey[candidate.generationKey] == nil {
                                desiredByKey[candidate.generationKey] = candidate
                            }
                        }
                    }
                case .rotation:
                    guard !templateDays.isEmpty else { continue }
                    let onDays = max(block.rotationOnDays ?? templateDays.count, 1)
                    let offDays = max(block.rotationOffDays ?? 0, 0)
                    let totalBlockDays = ((block.endWeekIndex - block.startWeekIndex) + 1) * 7
                    var workoutSequenceIndex = 0
                    for offset in 0..<totalBlockDays {
                        let cycleLength = max(onDays + offDays, 1)
                        let cycleDay = offset % cycleLength
                        let isWorkoutDay = cycleDay < onDays
                        if !isWorkoutDay { continue }
                        let templateDay = templateDays[workoutSequenceIndex % templateDays.count]
                        workoutSequenceIndex += 1
                        let week = block.startWeekIndex + (offset / 7)
                        guard effectiveRange.contains(week) else { continue }
                        let weekDay = offset % 7
                        let candidate = MaterializedTemplateCandidate(
                            generationKey: generationKey(
                                programId: program.id,
                                blockId: block.id,
                                templateDayId: templateDay.id,
                                weekIndex: week
                            ) + "|d\(weekDay)",
                            block: block,
                            templateDay: templateDay,
                            routine: templateDay.routine,
                            weekIndex: week,
                            dayIndex: weekDay,
                            order: templateDay.order,
                            title: storedWorkoutTitle(from: templateDay.title, routine: templateDay.routine)
                        )
                        if desiredByKey[candidate.generationKey] == nil {
                            desiredByKey[candidate.generationKey] = candidate
                        }
                    }
                }
            }
        }

        let desired = desiredByKey.values.sorted { lhs, rhs in
            if lhs.weekIndex != rhs.weekIndex { return lhs.weekIndex < rhs.weekIndex }
            if lhs.dayIndex != rhs.dayIndex { return lhs.dayIndex < rhs.dayIndex }
            return lhs.order < rhs.order
        }
        let existingGenerated = program.programDays.filter { $0.isGeneratedFromTemplate }
        var existingByKey: [String: ProgramDay] = [:]
        for day in existingGenerated {
            guard let key = day.generationKey else { continue }
            existingByKey[key] = day
        }

        for candidate in desired {
            if let existing = existingByKey[candidate.generationKey] {
                existing.sourceBlock = candidate.block
                existing.sourceTemplateDay = candidate.templateDay
                existing.routine = candidate.routine
                existing.weekIndex = candidate.weekIndex
                existing.dayIndex = candidate.dayIndex
                existing.order = candidate.order
                existing.title = candidate.title
            } else {
                let created = ProgramDay(
                    user_id: program.user_id,
                    program: program,
                    routine: candidate.routine,
                    sourceBlock: candidate.block,
                    sourceTemplateDay: candidate.templateDay,
                    isGeneratedFromTemplate: true,
                    generationKey: candidate.generationKey,
                    weekIndex: candidate.weekIndex,
                    dayIndex: candidate.dayIndex,
                    blockIndex: candidate.block.order,
                    title: candidate.title,
                    order: candidate.order
                )
                modelContext.insert(created)
                program.programDays.append(created)
            }
        }

        let shouldPrune = pruneStaleGeneratedRows ?? (program.resolvedProgramLengthMode == .fixedLength)
        if shouldPrune {
            for staleDay in existingGenerated {
                guard let key = staleDay.generationKey else { continue }
                guard desiredByKey[key] == nil else { continue }
                if staleDay.sessions.isEmpty {
                    modelContext.delete(staleDay)
                }
            }
        }

        do {
            try modelContext.save()
            loadPrograms()
            return true
        } catch {
            return false
        }
    }

    private func generationKey(
        programId: UUID,
        blockId: UUID,
        templateDayId: UUID,
        weekIndex: Int
    ) -> String {
        "\(programId.uuidString)|\(blockId.uuidString)|\(templateDayId.uuidString)|w\(weekIndex)"
    }

    private func sortedNonArchivedBlocks(for program: Program) -> [ProgramBlock] {
        program.blocks
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                if lhs.order != rhs.order { return lhs.order < rhs.order }
                return lhs.startWeekIndex < rhs.startWeekIndex
            }
    }

    private func resolvedBlock(for program: Program, weekIndex: Int) -> ProgramBlock? {
        let blocks = sortedNonArchivedBlocks(for: program)
        guard !blocks.isEmpty else { return nil }

        if let exact = blocks.first(where: { weekIndex >= $0.startWeekIndex && weekIndex <= $0.endWeekIndex }) {
            return exact
        }

        guard program.resolvedProgramLengthMode == .continuous else { return nil }

        if weekIndex < blocks[0].startWeekIndex {
            return blocks[0]
        }
        if let last = blocks.last, weekIndex > last.endWeekIndex {
            return last
        }

        // Continuous fallback for gaps: carry forward the last block whose start is before the target week.
        return blocks
            .filter { $0.startWeekIndex <= weekIndex }
            .sorted { $0.startWeekIndex > $1.startWeekIndex }
            .first ?? blocks[0]
    }

    private func intersectWeekRange(left: ClosedRange<Int>, right: ClosedRange<Int>?) -> ClosedRange<Int>? {
        guard let right else { return left }
        let lower = max(left.lowerBound, right.lowerBound)
        let upper = min(left.upperBound, right.upperBound)
        guard lower <= upper else { return nil }
        return lower...upper
    }

    private func addContinuousCandidates(
        to desiredByKey: inout [String: MaterializedTemplateCandidate],
        program: Program,
        weekRange: ClosedRange<Int>
    ) {
        // Phase 13 rule:
        // - continuous calendar uses resolved block per week
        // - continuous rotation keeps cadence anchored to program start (no unnecessary reset at block boundaries)
        for week in weekRange {
            guard let block = resolvedBlock(for: program, weekIndex: week) else { continue }
            let templateDays = block.templateDays.sorted { $0.order < $1.order }
            guard !templateDays.isEmpty else { continue }
            if block.resolvedScheduleMode == .calendar {
                for templateDay in templateDays {
                    let candidate = MaterializedTemplateCandidate(
                        generationKey: generationKey(
                            programId: program.id,
                            blockId: block.id,
                            templateDayId: templateDay.id,
                            weekIndex: week
                        ),
                        block: block,
                        templateDay: templateDay,
                        routine: templateDay.routine,
                        weekIndex: week,
                        dayIndex: templateDay.weekDayIndex,
                        order: templateDay.order,
                        title: storedWorkoutTitle(from: templateDay.title, routine: templateDay.routine)
                    )
                    if desiredByKey[candidate.generationKey] == nil {
                        desiredByKey[candidate.generationKey] = candidate
                    }
                }
            }
        }

        let maxAbsoluteDay = max((weekRange.upperBound + 1) * 7 - 1, 0)
        var globalWorkoutOrdinal = 0
        for absoluteDay in 0...maxAbsoluteDay {
            let week = absoluteDay / 7
            let weekDay = absoluteDay % 7
            guard let block = resolvedBlock(for: program, weekIndex: week) else { continue }
            guard block.resolvedScheduleMode == .rotation else { continue }
            let templateDays = block.templateDays.sorted { $0.order < $1.order }
            guard !templateDays.isEmpty else { continue }

            let onDays = max(block.rotationOnDays ?? templateDays.count, 1)
            let offDays = max(block.rotationOffDays ?? 0, 0)
            let cycleLength = max(onDays + offDays, 1)
            let cycleDay = absoluteDay % cycleLength
            let isWorkoutDay = cycleDay < onDays
            if !isWorkoutDay { continue }

            let templateDay = templateDays[globalWorkoutOrdinal % templateDays.count]
            globalWorkoutOrdinal += 1

            guard weekRange.contains(week) else { continue }
            let candidate = MaterializedTemplateCandidate(
                generationKey: generationKey(
                    programId: program.id,
                    blockId: block.id,
                    templateDayId: templateDay.id,
                    weekIndex: week
                ) + "|d\(weekDay)",
                block: block,
                templateDay: templateDay,
                routine: templateDay.routine,
                weekIndex: week,
                dayIndex: weekDay,
                order: templateDay.order,
                title: storedWorkoutTitle(from: templateDay.title, routine: templateDay.routine)
            )
            if desiredByKey[candidate.generationKey] == nil {
                desiredByKey[candidate.generationKey] = candidate
            }
        }
    }

    private func enforceSingleCurrentProgram(for userId: UUID, keep: Program) {
        let descriptor = FetchDescriptor<Program>(
            predicate: #Predicate<Program> { program in
                program.user_id == userId
            }
        )
        let matches = (try? modelContext.fetch(descriptor)) ?? []
        for match in matches where match.id != keep.id {
            match.isCurrent = false
        }
    }

    func displayBlockName(_ block: ProgramBlock) -> String {
        let trimmed = block.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Block \(block.order + 1)" : trimmed
    }

    func displayWorkoutName(for programDay: ProgramDay) -> String {
        let trimmed = programDay.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let routineName = programDay.routine?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !routineName.isEmpty { return routineName }
        return "Workout \(programDay.order + 1)"
    }

    func displayWorkoutName(for templateDay: ProgramBlockTemplateDay) -> String {
        let trimmed = templateDay.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let routineName = templateDay.routine?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !routineName.isEmpty { return routineName }
        return "Workout \(templateDay.order + 1)"
    }

    private func isValidRoutineForProgramOwner(_ routine: Routine?, ownerId: UUID) -> Bool {
        guard let routine else { return true }
        return routine.user_id == ownerId
    }

    private func createInitialBlockIfNeeded(for program: Program, userId: UUID) {
        guard program.blocks.isEmpty else { return }
        let block = ProgramBlock(
            user_id: userId,
            program: program,
            title: "",
            notes: "",
            startWeekIndex: 0,
            endWeekIndex: 3,
            order: 0,
            scheduleMode: .calendar
        )
        modelContext.insert(block)
    }

    private func storedWorkoutTitle(from title: String, routine: Routine?) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        let routineName = routine?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return routineName
    }

    private func weekdayLabel(for dayIndex: Int) -> String {
        let labels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        guard labels.indices.contains(dayIndex) else { return "Day \(dayIndex + 1)" }
        return labels[dayIndex]
    }

    private struct MaterializedTemplateCandidate {
        let generationKey: String
        let block: ProgramBlock
        let templateDay: ProgramBlockTemplateDay
        let routine: Routine?
        let weekIndex: Int
        let dayIndex: Int
        let order: Int
        let title: String
    }

}
