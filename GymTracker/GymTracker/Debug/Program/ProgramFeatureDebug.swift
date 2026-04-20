#if DEBUG
import Foundation
import SwiftData

final class ProgramFeatureDebug {
    private static var hasRun = false

    static func runSamples() {
        guard !hasRun else { return }
        hasRun = true

        print("=== ProgramFeatureDebug start ===")
        let results = [
            test1SessionCreationKeepsRoutineOrder(),
            test2ContinuousProgramAdvancesAfterFullSplits(),
            test3WeeklyProgramUsesCalendarWeeksAndSessionSnapshots(),
            test4UsedProgramArchivesAndHistoryStillResolves(),
            test5UnusedProgramDeletesNormally(),
            test6ContinuousSkipAdvancesAndPersists(),
            test7WeeklySkipAdvancesWithinWeekAndResetsNextWeek()
        ]
        let passCount = results.filter { $0 }.count
        print("=== ProgramFeatureDebug done: \(passCount)/\(results.count) passed ===")
    }

    @discardableResult
    private static func test1SessionCreationKeepsRoutineOrder() -> Bool {
        do {
            let harness = try makeHarness()
            let user = User(name: "Session Order User")
            harness.context.insert(user)

            let routine = Routine(order: 0, name: "Ordered Routine", user_id: user.id)
            let squat = Exercise(name: "Squat", type: .weight, user_id: user.id)
            let bench = Exercise(name: "Bench", type: .weight, user_id: user.id)
            let row = Exercise(name: "Row", type: .weight, user_id: user.id)
            harness.context.insert(routine)
            harness.context.insert(squat)
            harness.context.insert(bench)
            harness.context.insert(row)

            let split2 = ExerciseSplitDay(order: 2, routine: routine, exercise: row)
            let split0 = ExerciseSplitDay(order: 0, routine: routine, exercise: squat)
            let split1 = ExerciseSplitDay(order: 1, routine: routine, exercise: bench)
            harness.context.insert(split2)
            harness.context.insert(split0)
            harness.context.insert(split1)
            routine.exerciseSplits.append(split2)
            routine.exerciseSplits.append(split0)
            routine.exerciseSplits.append(split1)
            try harness.context.save()

            let sessionRepository = LocalSessionRepository(modelContext: harness.context)
            let session = try sessionRepository.createSession(userId: user.id, routine: routine, notes: "")

            let orderedEntries = session.sessionEntries.sorted { lhs, rhs in
                if lhs.order != rhs.order {
                    return lhs.order < rhs.order
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }

            var ok = true
            ok = ok && check("program-test1", orderedEntries.map(\.order) == [0, 1, 2], "Expected copied session entry order values to be sequential")
            ok = ok && check("program-test1", orderedEntries.map(\.exercise.id) == [squat.id, bench.id, row.id], "Expected session entries to follow the routine exercise order, not relationship storage order")
            print("[program-test1] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("program-test1", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func test2ContinuousProgramAdvancesAfterFullSplits() -> Bool {
        do {
            let harness = try makeHarness()
            let user = User(name: "Program User")
            harness.context.insert(user)

            let routineA = Routine(order: 0, name: "Push", user_id: user.id)
            let routineB = Routine(order: 1, name: "Pull", user_id: user.id)
            let routineC = Routine(order: 2, name: "Legs", user_id: user.id)
            harness.context.insert(routineA)
            harness.context.insert(routineB)
            harness.context.insert(routineC)
            try harness.context.save()

            let programService = ProgramService(context: harness.context)
            programService.currentUser = user
            let sessionRepository = LocalSessionRepository(modelContext: harness.context)

            guard let program = programService.createProgram(
                name: "Continuous MVP",
                mode: .continuous,
                startDate: date(2026, 4, 6)
            ) else {
                return fail("program-test2", "Expected program creation to succeed")
            }

            guard let block1 = programService.addBlock(to: program, name: "Block 1", durationCount: 2),
                  let workoutA = programService.addWorkout(to: block1, routine: routineA, name: nil, weekdayIndex: nil),
                  let workoutB = programService.addWorkout(to: block1, routine: routineB, name: nil, weekdayIndex: nil),
                  let block2 = programService.addBlock(to: program, name: "Block 2", durationCount: 1),
                  let workoutC = programService.addWorkout(to: block2, routine: routineC, name: nil, weekdayIndex: nil) else {
                return fail("program-test2", "Expected blocks and workouts to be created")
            }

            for (index, workout) in [workoutA, workoutB, workoutA, workoutB].enumerated() {
                let session = try sessionRepository.createProgramSession(
                    userId: user.id,
                    program: program,
                    programBlock: block1,
                    programWorkout: workout,
                    notes: "completed-\(index)",
                    programWeekIndex: nil,
                    programSplitIndex: (index / 2) + 1
                )
                session.timestampDone = session.timestamp.addingTimeInterval(60)
                try sessionRepository.saveChanges(for: session)
            }

            let sessions = try sessionRepository.fetchSessions(for: user.id)
            let state = programService.resolvedState(for: program, sessions: sessions)

            var ok = true
            ok = ok && check("program-test2", state.currentBlock?.id == block2.id, "Expected the next block after two full split passes")
            ok = ok && check("program-test2", state.nextWorkout?.id == workoutC.id, "Expected the next workout to be the first workout in block 2")
            ok = ok && check("program-test2", state.activeSession == nil, "Expected no active session after completing all block 1 workouts")
            print("[program-test2] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("program-test2", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func test3WeeklyProgramUsesCalendarWeeksAndSessionSnapshots() -> Bool {
        do {
            let harness = try makeHarness()
            let user = User(name: "Weekly User")
            harness.context.insert(user)

            let routineA = Routine(order: 0, name: "Upper", user_id: user.id)
            let routineB = Routine(order: 1, name: "Lower", user_id: user.id)
            let routineC = Routine(order: 2, name: "Conditioning", user_id: user.id)
            harness.context.insert(routineA)
            harness.context.insert(routineB)
            harness.context.insert(routineC)
            try harness.context.save()

            let programService = ProgramService(context: harness.context)
            programService.currentUser = user
            let sessionRepository = LocalSessionRepository(modelContext: harness.context)
            let calendar = Calendar(identifier: .gregorian)
            let startDate = date(2026, 4, 6)

            guard let program = programService.createProgram(
                name: "Weekly MVP",
                mode: .weekly,
                startDate: startDate
            ) else {
                return fail("program-test3", "Expected weekly program creation to succeed")
            }

            guard let block1 = programService.addBlock(to: program, name: "Weeks 1-2", durationCount: 2),
                  let mondayWorkout = programService.addWorkout(to: block1, routine: routineA, name: nil, weekdayIndex: ProgramWeekday.monday.rawValue),
                  let wednesdayWorkout = programService.addWorkout(to: block1, routine: routineB, name: nil, weekdayIndex: ProgramWeekday.wednesday.rawValue),
                  let block2 = programService.addBlock(to: program, name: "Week 3", durationCount: 1),
                  let fridayWorkout = programService.addWorkout(to: block2, routine: routineC, name: nil, weekdayIndex: ProgramWeekday.friday.rawValue) else {
                return fail("program-test3", "Expected weekly blocks and workouts to be created")
            }

            let weekTwoReference = calendar.date(byAdding: .day, value: 9, to: startDate) ?? startDate
            let weekThreeReference = calendar.date(byAdding: .day, value: 15, to: startDate) ?? startDate

            let weekTwoState = programService.resolvedState(
                for: program,
                sessions: [],
                referenceDate: weekTwoReference,
                calendar: calendar
            )
            let weekThreeState = programService.resolvedState(
                for: program,
                sessions: [],
                referenceDate: weekThreeReference,
                calendar: calendar
            )

            let session = try sessionRepository.createProgramSession(
                userId: user.id,
                program: program,
                programBlock: block1,
                programWorkout: wednesdayWorkout,
                notes: "Week 2 workout",
                programWeekIndex: 2,
                programSplitIndex: nil
            )

            var ok = true
            ok = ok && check("program-test3", weekTwoState.currentBlock?.id == block1.id, "Expected week 2 to remain in the first block")
            ok = ok && check("program-test3", weekTwoState.nextWorkout?.id == wednesdayWorkout.id, "Expected Wednesday workout during week 2 reference date")
            ok = ok && check("program-test3", weekTwoState.progressLabel == "Week 2 of 2", "Expected week progress label to use calendar weeks")
            ok = ok && check("program-test3", weekThreeState.currentBlock?.id == block2.id, "Expected week 3 to advance to the next block")
            ok = ok && check("program-test3", weekThreeState.nextWorkout?.id == fridayWorkout.id, "Expected block 2 workout after week transition")
            ok = ok && check("program-test3", session.programBlockId == block1.id, "Expected session to snapshot the originating block id")
            ok = ok && check("program-test3", session.programWorkoutId == wednesdayWorkout.id, "Expected session to snapshot the originating workout id")
            ok = ok && check("program-test3", session.programWeekIndex == 2, "Expected session to snapshot the computed week index")
            ok = ok && check("program-test3", session.routine?.id == routineB.id, "Expected session to keep the linked routine")
            ok = ok && check("program-test3", mondayWorkout.weekdayIndex == ProgramWeekday.monday.rawValue, "Expected weekday scheduling to persist")
            print("[program-test3] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("program-test3", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func test4UsedProgramArchivesAndHistoryStillResolves() -> Bool {
        do {
            let harness = try makeHarness()
            let user = User(name: "Archive User")
            harness.context.insert(user)

            let routine = Routine(order: 0, name: "Push", user_id: user.id)
            harness.context.insert(routine)
            try harness.context.save()

            let programService = ProgramService(context: harness.context)
            programService.currentUser = user
            let sessionRepository = LocalSessionRepository(modelContext: harness.context)

            guard let program = programService.createProgram(
                name: "Used Program",
                mode: .continuous,
                startDate: date(2026, 4, 6)
            ),
            let hiddenBlock = programService.directWorkoutBlock(for: program),
            let workout = programService.addWorkout(to: hiddenBlock, routine: routine, name: nil, weekdayIndex: nil) else {
                return fail("program-test4", "Expected used program setup to succeed")
            }

            let session = try sessionRepository.createProgramSession(
                userId: user.id,
                program: program,
                programBlock: hiddenBlock,
                programWorkout: workout,
                notes: "used",
                programWeekIndex: nil,
                programSplitIndex: 1
            )
            session.timestampDone = session.timestamp.addingTimeInterval(60)
            try sessionRepository.saveChanges(for: session)

            let shouldArchive = programService.willArchiveOnDelete(program)
            programService.delete(program)
            programService.loadPrograms()

            let fetchedSessions = try sessionRepository.fetchSessions(for: user.id)

            var ok = true
            ok = ok && check("program-test4", shouldArchive, "Expected used program delete flow to archive instead")
            ok = ok && check("program-test4", programService.programs.contains(where: { $0.id == program.id }) == false, "Expected archived program to leave the active list")
            ok = ok && check("program-test4", programService.archivedPrograms.contains(where: { $0.id == program.id }), "Expected archived program to appear in archived programs")
            ok = ok && check("program-test4", fetchedSessions.first?.program?.id == program.id, "Expected archived program relation to remain available from session history")
            ok = ok && check("program-test4", fetchedSessions.first?.program?.name == "Used Program", "Expected program name to resolve through the archived program relation")
            print("[program-test4] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("program-test4", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func test5UnusedProgramDeletesNormally() -> Bool {
        do {
            let harness = try makeHarness()
            let user = User(name: "Delete User")
            harness.context.insert(user)
            try harness.context.save()

            let programService = ProgramService(context: harness.context)
            programService.currentUser = user

            guard let program = programService.createProgram(
                name: "Unused Program",
                mode: .continuous,
                startDate: date(2026, 4, 6)
            ) else {
                return fail("program-test5", "Expected unused program creation to succeed")
            }

            let shouldArchive = programService.willArchiveOnDelete(program)
            programService.delete(program)
            programService.loadPrograms()

            let allPrograms = try harness.context.fetch(FetchDescriptor<Program>())

            var ok = true
            ok = ok && check("program-test5", shouldArchive == false, "Expected unused programs to delete instead of archive")
            ok = ok && check("program-test5", allPrograms.contains(where: { $0.id == program.id }) == false, "Expected unused program to be removed from the store")
            ok = ok && check("program-test5", programService.archivedPrograms.contains(where: { $0.id == program.id }) == false, "Expected unused program not to appear in archived programs")
            print("[program-test5] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("program-test5", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func test6ContinuousSkipAdvancesAndPersists() -> Bool {
        do {
            let harness = try makeHarness()
            let user = User(name: "Continuous Skip User")
            harness.context.insert(user)

            let routineA = Routine(order: 0, name: "Push", user_id: user.id)
            let routineB = Routine(order: 1, name: "Pull", user_id: user.id)
            let routineC = Routine(order: 2, name: "Legs", user_id: user.id)
            harness.context.insert(routineA)
            harness.context.insert(routineB)
            harness.context.insert(routineC)
            try harness.context.save()

            let programService = ProgramService(context: harness.context)
            programService.currentUser = user

            guard let program = programService.createProgram(
                name: "Continuous Skip",
                mode: .continuous,
                startDate: date(2026, 4, 6)
            ),
            let block1 = programService.addBlock(to: program, name: "Block 1", durationCount: 1),
            let workoutA = programService.addWorkout(to: block1, routine: routineA, name: nil, weekdayIndex: nil),
            let workoutB = programService.addWorkout(to: block1, routine: routineB, name: nil, weekdayIndex: nil),
            let block2 = programService.addBlock(to: program, name: "Block 2", durationCount: 1),
            let workoutC = programService.addWorkout(to: block2, routine: routineC, name: nil, weekdayIndex: nil) else {
                return fail("program-test6", "Expected continuous program setup to succeed")
            }

            let initialState = programService.resolvedState(for: program, sessions: [])
            programService.skipNextWorkout(for: program, sessions: [])
            let afterFirstSkipProgram = programService.programs.first(where: { $0.id == program.id }) ?? program
            let afterFirstSkipState = programService.resolvedState(for: afterFirstSkipProgram, sessions: [])

            let reloadedService = ProgramService(context: harness.context)
            reloadedService.currentUser = user
            reloadedService.loadPrograms()
            guard let reloadedProgram = reloadedService.programs.first(where: { $0.id == program.id }) else {
                return fail("program-test6", "Expected skipped program to reload")
            }
            let reloadedState = reloadedService.resolvedState(for: reloadedProgram, sessions: [])

            reloadedService.skipNextWorkout(for: reloadedProgram, sessions: [])
            let afterSecondSkipProgram = reloadedService.programs.first(where: { $0.id == reloadedProgram.id }) ?? reloadedProgram
            let afterSecondSkipState = reloadedService.resolvedState(for: afterSecondSkipProgram, sessions: [])

            var ok = true
            ok = ok && check("program-test6", initialState.nextWorkout?.id == workoutA.id, "Expected first workout before any skips")
            ok = ok && check("program-test6", afterFirstSkipState.nextWorkout?.id == workoutB.id, "Expected first skip to advance to the second workout")
            ok = ok && check("program-test6", reloadedState.nextWorkout?.id == workoutB.id, "Expected continuous skip cursor to persist after reload")
            ok = ok && check("program-test6", afterSecondSkipState.currentBlock?.id == block2.id, "Expected second skip to advance into the next block")
            ok = ok && check("program-test6", afterSecondSkipState.nextWorkout?.id == workoutC.id, "Expected second skip to land on block 2's first workout")
            print("[program-test6] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("program-test6", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func test7WeeklySkipAdvancesWithinWeekAndResetsNextWeek() -> Bool {
        do {
            let harness = try makeHarness()
            let user = User(name: "Weekly Skip User")
            harness.context.insert(user)

            let mondayRoutine = Routine(order: 0, name: "Monday", user_id: user.id)
            let wednesdayRoutine = Routine(order: 1, name: "Wednesday", user_id: user.id)
            let fridayRoutine = Routine(order: 2, name: "Friday", user_id: user.id)
            harness.context.insert(mondayRoutine)
            harness.context.insert(wednesdayRoutine)
            harness.context.insert(fridayRoutine)
            try harness.context.save()

            let programService = ProgramService(context: harness.context)
            programService.currentUser = user
            let mondayReference = date(2026, 4, 6)
            let nextWeekReference = date(2026, 4, 13)

            guard let program = programService.createProgram(
                name: "Weekly Skip",
                mode: .weekly,
                startDate: mondayReference
            ),
            let block = programService.addBlock(to: program, name: "Weeks 1-2", durationCount: 2),
            let mondayWorkout = programService.addWorkout(to: block, routine: mondayRoutine, name: nil, weekdayIndex: ProgramWeekday.monday.rawValue),
            let wednesdayWorkout = programService.addWorkout(to: block, routine: wednesdayRoutine, name: nil, weekdayIndex: ProgramWeekday.wednesday.rawValue),
            let fridayWorkout = programService.addWorkout(to: block, routine: fridayRoutine, name: nil, weekdayIndex: ProgramWeekday.friday.rawValue) else {
                return fail("program-test7", "Expected weekly program setup to succeed")
            }

            let initialState = programService.resolvedState(
                for: program,
                sessions: [],
                referenceDate: mondayReference
            )
            programService.skipNextWorkout(
                for: program,
                sessions: [],
                referenceDate: mondayReference
            )
            let skippedProgram = programService.programs.first(where: { $0.id == program.id }) ?? program
            let afterSkipState = programService.resolvedState(
                for: skippedProgram,
                sessions: [],
                referenceDate: mondayReference
            )

            let reloadedService = ProgramService(context: harness.context)
            reloadedService.currentUser = user
            reloadedService.loadPrograms()
            guard let reloadedProgram = reloadedService.programs.first(where: { $0.id == program.id }) else {
                return fail("program-test7", "Expected weekly skipped program to reload")
            }
            let reloadedState = reloadedService.resolvedState(
                for: reloadedProgram,
                sessions: [],
                referenceDate: mondayReference
            )
            let nextWeekState = reloadedService.resolvedState(
                for: reloadedProgram,
                sessions: [],
                referenceDate: nextWeekReference
            )

            var ok = true
            ok = ok && check("program-test7", initialState.nextWorkout?.id == mondayWorkout.id, "Expected Monday workout at the start of the week")
            ok = ok && check("program-test7", afterSkipState.nextWorkout?.id == wednesdayWorkout.id, "Expected skipping Monday to advance to Wednesday")
            ok = ok && check("program-test7", reloadedState.nextWorkout?.id == wednesdayWorkout.id, "Expected weekly skip cursor to persist inside the same week")
            ok = ok && check("program-test7", nextWeekState.nextWorkout?.id == mondayWorkout.id, "Expected weekly skip cursor to reset on the next program week")
            ok = ok && check("program-test7", nextWeekState.nextWorkout?.id != fridayWorkout.id, "Expected the next week to no longer use the prior week's skipped cursor")
            print("[program-test7] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("program-test7", "Unexpected error: \(error)")
        }
    }

    private struct Harness {
        let container: ModelContainer
        let context: ModelContext
    }

    private static func makeHarness() throws -> Harness {
        let schema = Schema([
            User.self,
            Routine.self,
            Exercise.self,
            ExerciseSplitDay.self,
            Session.self,
            SessionEntry.self,
            SessionSet.self,
            SessionRep.self,
            Program.self,
            ProgramBlock.self,
            ProgramWorkout.self
        ])

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        return Harness(container: container, context: context)
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    @discardableResult
    private static func check(_ test: String, _ condition: Bool, _ message: String) -> Bool {
        if !condition {
            print("[\(test)] FAIL: \(message)")
        }
        return condition
    }

    @discardableResult
    private static func fail(_ test: String, _ message: String) -> Bool {
        print("[\(test)] FAIL: \(message)")
        return false
    }
}
#endif
