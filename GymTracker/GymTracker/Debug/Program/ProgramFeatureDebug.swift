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
            test1ContinuousProgramAdvancesAfterFullSplits(),
            test2WeeklyProgramUsesCalendarWeeksAndSessionSnapshots()
        ]
        let passCount = results.filter { $0 }.count
        print("=== ProgramFeatureDebug done: \(passCount)/\(results.count) passed ===")
    }

    @discardableResult
    private static func test1ContinuousProgramAdvancesAfterFullSplits() -> Bool {
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
                return fail("program-test1", "Expected program creation to succeed")
            }

            guard let block1 = programService.addBlock(to: program, name: "Block 1", durationCount: 2),
                  let workoutA = programService.addWorkout(to: block1, routine: routineA, name: nil, weekdayIndex: nil),
                  let workoutB = programService.addWorkout(to: block1, routine: routineB, name: nil, weekdayIndex: nil),
                  let block2 = programService.addBlock(to: program, name: "Block 2", durationCount: 1),
                  let workoutC = programService.addWorkout(to: block2, routine: routineC, name: nil, weekdayIndex: nil) else {
                return fail("program-test1", "Expected blocks and workouts to be created")
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
            ok = ok && check("program-test1", state.currentBlock?.id == block2.id, "Expected the next block after two full split passes")
            ok = ok && check("program-test1", state.nextWorkout?.id == workoutC.id, "Expected the next workout to be the first workout in block 2")
            ok = ok && check("program-test1", state.activeSession == nil, "Expected no active session after completing all block 1 workouts")
            print("[program-test1] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("program-test1", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func test2WeeklyProgramUsesCalendarWeeksAndSessionSnapshots() -> Bool {
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
                return fail("program-test2", "Expected weekly program creation to succeed")
            }

            guard let block1 = programService.addBlock(to: program, name: "Weeks 1-2", durationCount: 2),
                  let mondayWorkout = programService.addWorkout(to: block1, routine: routineA, name: nil, weekdayIndex: ProgramWeekday.monday.rawValue),
                  let wednesdayWorkout = programService.addWorkout(to: block1, routine: routineB, name: nil, weekdayIndex: ProgramWeekday.wednesday.rawValue),
                  let block2 = programService.addBlock(to: program, name: "Week 3", durationCount: 1),
                  let fridayWorkout = programService.addWorkout(to: block2, routine: routineC, name: nil, weekdayIndex: ProgramWeekday.friday.rawValue) else {
                return fail("program-test2", "Expected weekly blocks and workouts to be created")
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
            ok = ok && check("program-test2", weekTwoState.currentBlock?.id == block1.id, "Expected week 2 to remain in the first block")
            ok = ok && check("program-test2", weekTwoState.nextWorkout?.id == wednesdayWorkout.id, "Expected Wednesday workout during week 2 reference date")
            ok = ok && check("program-test2", weekTwoState.progressLabel == "Week 2 of 2", "Expected week progress label to use calendar weeks")
            ok = ok && check("program-test2", weekThreeState.currentBlock?.id == block2.id, "Expected week 3 to advance to the next block")
            ok = ok && check("program-test2", weekThreeState.nextWorkout?.id == fridayWorkout.id, "Expected block 2 workout after week transition")
            ok = ok && check("program-test2", session.programBlockId == block1.id, "Expected session to snapshot the originating block id")
            ok = ok && check("program-test2", session.programWorkoutId == wednesdayWorkout.id, "Expected session to snapshot the originating workout id")
            ok = ok && check("program-test2", session.programWeekIndex == 2, "Expected session to snapshot the computed week index")
            ok = ok && check("program-test2", session.routine?.id == routineB.id, "Expected session to keep the linked routine")
            ok = ok && check("program-test2", mondayWorkout.weekdayIndex == ProgramWeekday.monday.rawValue, "Expected weekday-based workout scheduling to persist")
            print("[program-test2] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("program-test2", "Unexpected error: \(error)")
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
