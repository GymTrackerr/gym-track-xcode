#if DEBUG
import Foundation
import SwiftData

enum Phase9HardeningDebug {
    static func runSamples() {
        print("=== Phase9HardeningDebug start ===")
        let results = [
            testRoutineScopingAndProgramDayRoutineOwnership(),
            testProfileDefaultRepsFallback()
        ]
        let passCount = results.filter { $0 }.count
        print("=== Phase9HardeningDebug done: \(passCount)/\(results.count) passed ===")
    }

    @discardableResult
    private static func testRoutineScopingAndProgramDayRoutineOwnership() -> Bool {
        do {
            let harness = try makeHarness()
            let userA = User(name: "Phase9 User A")
            let userB = User(name: "Phase9 User B")
            harness.context.insert(userA)
            harness.context.insert(userB)

            let routineA = Routine(order: 0, name: "Routine A", user_id: userA.id)
            let routineB = Routine(order: 0, name: "Routine B", user_id: userB.id)
            harness.context.insert(routineA)
            harness.context.insert(routineB)

            let programService = ProgramService(context: harness.context)
            let routineService = RoutineService(context: harness.context)
            programService.currentUser = userA
            routineService.currentUser = userA

            guard let program = programService.addProgram(name: "Phase9 Program") else {
                return fail("phase9-test1", "Expected program creation")
            }

            routineService.loadSplitDays()
            var ok = true
            ok = ok && check("phase9-test1", routineService.routines.count == 1, "Expected routine list to be user-scoped")
            ok = ok && check("phase9-test1", routineService.routines.first?.id == routineA.id, "Expected only same-user routine")

            let blocked = programService.addProgramDay(
                to: program,
                title: "Blocked Foreign Routine",
                weekIndex: 0,
                dayIndex: 0,
                blockIndex: nil,
                routine: routineB
            )
            ok = ok && check("phase9-test1", blocked == nil, "Expected foreign-user routine assignment to be blocked")

            let allowed = programService.addProgramDay(
                to: program,
                title: "Allowed Same User Routine",
                weekIndex: 0,
                dayIndex: 1,
                blockIndex: nil,
                routine: routineA
            )
            ok = ok && check("phase9-test1", allowed != nil, "Expected same-user routine assignment to succeed")

            print("[phase9-test1] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("phase9-test1", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func testProfileDefaultRepsFallback() -> Bool {
        do {
            let harness = try makeHarness()
            let user = User(name: "Phase9 Defaults User")
            harness.context.insert(user)

            let progression = ProgressionProfile(
                user_id: user.id,
                name: "Profile With Default Reps",
                type: .linear,
                requiredSuccessSessions: 2,
                incrementValue: 5,
                incrementUnit: .pounds,
                successPolicy: .allTargetsMet,
                defaultRepsTarget: 10
            )
            harness.context.insert(progression)

            let userDefault = UserProgressionDefault(user_id: user.id, progression: progression)
            harness.context.insert(userDefault)

            let exercise = Exercise(name: "Fallback Exercise", type: .weight, user_id: user.id)
            harness.context.insert(exercise)
            let session = Session(timestamp: Date(), user_id: user.id, routine: nil, notes: "")
            harness.context.insert(session)
            let entry = SessionEntry(order: 0, session: session, exercise: exercise)
            harness.context.insert(entry)

            let setService = SetService(context: harness.context)
            setService.currentUser = user
            let defaultsService = ProgressionDefaultsService(context: harness.context, setService: setService)
            defaultsService.currentUser = user

            let applied = defaultsService.applyDefaultsIfAvailable(to: entry)
            let ok = check("phase9-test2", applied, "Expected defaults to apply")
                && check("phase9-test2", entry.appliedRepsTarget == 10, "Expected profile default reps target fallback")
                && check("phase9-test2", entry.appliedProgression?.id == progression.id, "Expected progression to be applied")

            print("[phase9-test2] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("phase9-test2", "Unexpected error: \(error)")
        }
    }

    private struct Harness {
        let container: ModelContainer
        let context: ModelContext
    }

    private static func makeHarness() throws -> Harness {
        let schema = Schema([
            User.self,
            Exercise.self,
            Session.self,
            SessionEntry.self,
            SessionSet.self,
            SessionRep.self,
            Routine.self,
            ExerciseSplitDay.self,
            Program.self,
            ProgramBlock.self,
            ProgramBlockTemplateDay.self,
            ProgramDay.self,
            ProgramDayExerciseOverride.self,
            ProgressionProfile.self,
            ProgressionState.self,
            ExerciseProgressionDefault.self,
            UserProgressionDefault.self
        ])

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        return Harness(container: container, context: context)
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
