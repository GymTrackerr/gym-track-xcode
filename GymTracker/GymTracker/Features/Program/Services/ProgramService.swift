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
            isBuiltIn: isBuiltIn,
            builtInKey: builtInKey,
            startDate: startDate
        )
        modelContext.insert(created)

        do {
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
        startDate: Date?
    ) -> Bool {
        guard !program.isBuiltIn else { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }

        program.name = trimmedName
        program.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        program.isActive = isActive
        program.startDate = startDate

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
    func archiveProgram(_ program: Program) -> Bool {
        guard !program.isBuiltIn else { return false }
        program.isArchived = true
        program.isActive = false
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
            isBuiltIn: false,
            builtInKey: nil,
            startDate: program.startDate
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
