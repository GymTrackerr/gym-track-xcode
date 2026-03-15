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

        do {
            if isCurrent {
                enforceSingleCurrentProgram(for: userId, keep: created)
            }
            try modelContext.save()
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
        isCurrent: Bool
    ) -> Bool {
        guard !program.isBuiltIn else { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }

        program.name = trimmedName
        program.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        program.isActive = isActive
        program.startDate = startDate
        program.isCurrent = isCurrent

        do {
            if isCurrent {
                enforceSingleCurrentProgram(for: program.user_id, keep: program)
            }
            try modelContext.save()
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
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        let nextOrder = (program.programDays.map(\.order).max() ?? -1) + 1
        let created = ProgramDay(
            user_id: userId,
            program: program,
            routine: routine,
            weekIndex: max(0, weekIndex),
            dayIndex: max(0, dayIndex),
            blockIndex: blockIndex,
            title: trimmedTitle,
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
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return false }

        programDay.title = trimmedTitle
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
        do {
            try modelContext.save()
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
        return program.blocks
            .filter { $0.isArchived == false }
            .sorted { $0.order < $1.order }
            .first(where: { week >= $0.startWeekIndex && week <= $0.endWeekIndex })
    }

    func nextScheduledDay(for program: Program) -> ProgramDay? {
        let currentWeek = effectiveCurrentWeek(for: program)
        let todayWeekdayIndex = Calendar.current.component(.weekday, from: Date()) - 1
        let sorted = program.programDays.sorted(by: { lhs, rhs in
            if lhs.weekIndex != rhs.weekIndex { return lhs.weekIndex < rhs.weekIndex }
            if lhs.dayIndex != rhs.dayIndex { return lhs.dayIndex < rhs.dayIndex }
            return lhs.order < rhs.order
        })

        if let currentWeekCandidate = sorted.first(where: { day in
            day.weekIndex == currentWeek && day.dayIndex >= todayWeekdayIndex
        }) {
            return currentWeekCandidate
        }

        return sorted.first(where: { $0.weekIndex > currentWeek })
    }

    func nextScheduledDayText(for program: Program) -> String? {
        guard let day = nextScheduledDay(for: program) else { return nil }
        let weekdayLabel = weekdayLabel(for: day.dayIndex)
        let routineName = day.routine?.name ?? "No routine"
        return "\(weekdayLabel) · Week \(day.weekIndex + 1) · \(routineName)"
    }

    @discardableResult
    func addBlock(
        to program: Program,
        title: String,
        notes: String = "",
        startWeekIndex: Int,
        endWeekIndex: Int
    ) -> ProgramBlock? {
        guard !program.isBuiltIn else { return nil }
        guard let userId = currentUser?.id else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let nextOrder = (program.blocks.map(\.order).max() ?? -1) + 1
        let block = ProgramBlock(
            user_id: userId,
            program: program,
            title: trimmed,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            startWeekIndex: max(0, startWeekIndex),
            endWeekIndex: max(startWeekIndex, endWeekIndex),
            order: nextOrder
        )
        modelContext.insert(block)
        do {
            try modelContext.save()
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
        endWeekIndex: Int
    ) -> Bool {
        guard block.program?.isBuiltIn != true else { return false }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        block.title = trimmed
        block.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        block.startWeekIndex = max(0, startWeekIndex)
        block.endWeekIndex = max(block.startWeekIndex, endWeekIndex)
        do {
            try modelContext.save()
            loadPrograms()
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func removeBlock(_ block: ProgramBlock) -> Bool {
        guard block.program?.isBuiltIn != true else { return false }
        let generatedRows = block.materializedProgramDays.filter { $0.isGeneratedFromTemplate }
        if generatedRows.contains(where: { !$0.sessions.isEmpty }) { return false }
        for row in generatedRows {
            modelContext.delete(row)
        }
        modelContext.delete(block)
        do {
            try modelContext.save()
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
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let nextOrder = (block.templateDays.map(\.order).max() ?? -1) + 1
        let day = ProgramBlockTemplateDay(
            user_id: userId,
            block: block,
            routine: routine,
            title: trimmed,
            weekDayIndex: max(0, min(6, weekDayIndex)),
            order: nextOrder,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        modelContext.insert(day)
        do {
            try modelContext.save()
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
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        templateDay.title = trimmed
        templateDay.weekDayIndex = max(0, min(6, weekDayIndex))
        templateDay.routine = routine
        templateDay.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try modelContext.save()
            loadPrograms()
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func removeTemplateDay(_ templateDay: ProgramBlockTemplateDay) -> Bool {
        guard templateDay.block?.program?.isBuiltIn != true else { return false }
        let generatedRows = templateDay.materializedProgramDays.filter { $0.isGeneratedFromTemplate }
        if generatedRows.contains(where: { !$0.sessions.isEmpty }) { return false }
        for row in generatedRows {
            modelContext.delete(row)
        }
        modelContext.delete(templateDay)
        do {
            try modelContext.save()
            loadPrograms()
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func materializeTemplateSchedule(for program: Program) -> Bool {
        guard !program.isBuiltIn else { return false }
        let blocks = program.blocks.filter { !$0.isArchived }.sorted { $0.order < $1.order }
        var desiredByKey: [String: MaterializedTemplateCandidate] = [:]
        for block in blocks {
            guard block.endWeekIndex >= block.startWeekIndex else { continue }
            let templateDays = block.templateDays.sorted { $0.order < $1.order }
            for templateDay in templateDays {
                for week in block.startWeekIndex...block.endWeekIndex {
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
                        title: templateDay.title
                    )
                    if desiredByKey[candidate.generationKey] == nil {
                        desiredByKey[candidate.generationKey] = candidate
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

        for staleDay in existingGenerated {
            guard let key = staleDay.generationKey else { continue }
            guard desiredByKey[key] == nil else { continue }
            if staleDay.sessions.isEmpty {
                modelContext.delete(staleDay)
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

    func weekDayText(for program: Program) -> String? {
        if let latestSessionDay = latestProgramDayFromSession(for: program) {
            return "Week \(latestSessionDay.weekIndex + 1) · Day \(latestSessionDay.dayIndex + 1)"
        }

        guard let firstDay = firstProgramDay(for: program) else { return nil }
        return "Week \(firstDay.weekIndex + 1) · Day \(firstDay.dayIndex + 1)"
    }

    func nextRoutineText(for program: Program) -> String? {
        if let latestSessionDay = latestProgramDayFromSession(for: program) {
            return latestSessionDay.routine?.name
        }

        return firstProgramDay(for: program)?.routine?.name
    }

    private func firstProgramDay(for program: Program) -> ProgramDay? {
        program.programDays
            .sorted(by: { lhs, rhs in
                if lhs.weekIndex != rhs.weekIndex { return lhs.weekIndex < rhs.weekIndex }
                if lhs.dayIndex != rhs.dayIndex { return lhs.dayIndex < rhs.dayIndex }
                return lhs.order < rhs.order
            })
            .first
    }

    private func latestProgramDayFromSession(for program: Program) -> ProgramDay? {
        program.sessions
            .sorted(by: { $0.timestamp > $1.timestamp })
            .first?
            .programDay
    }
}
