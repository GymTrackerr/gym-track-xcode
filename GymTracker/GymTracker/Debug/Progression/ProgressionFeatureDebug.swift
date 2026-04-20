#if DEBUG
import Foundation
import SwiftData

final class ProgressionFeatureDebug {
    private static var hasRun = false

    static func runSamples() {
        guard !hasRun else { return }
        hasRun = true

        print("=== ProgressionFeatureDebug start ===")
        let results = [
            test1BackfillSeedsFromHistoryWithoutMutatingOldSessions(),
            test2LinearProgressionAdvancesAcrossSessionsAndIgnoresDuplicateEvaluation(),
            test3DoubleProgressionSuggestsRangeAndDoesNotStayStuck(),
            test4VolumeProgressionIncreasesSets(),
            test5SourceResolutionUsesRoutineProgramAndUserFallback(),
            test6ExplicitOverrideBeatsInheritedDefaults()
        ]
        let passCount = results.filter { $0 }.count
        print("=== ProgressionFeatureDebug done: \(passCount)/\(results.count) passed ===")
    }

    @discardableResult
    private static func test1BackfillSeedsFromHistoryWithoutMutatingOldSessions() -> Bool {
        do {
            let harness = try makeHarness()
            let user = User(name: "Backfill User")
            harness.context.insert(user)

            let exercise = Exercise(name: "Bench Press", type: .weight, user_id: user.id)
            harness.context.insert(exercise)

            let historicalSession = Session(timestamp: Date().addingTimeInterval(-3600), user_id: user.id, routine: nil, notes: "")
            historicalSession.timestampDone = historicalSession.timestamp.addingTimeInterval(300)
            harness.context.insert(historicalSession)
            let historicalEntry = SessionEntry(order: 0, session: historicalSession, exercise: exercise)
            harness.context.insert(historicalEntry)
            addStrengthSet(to: historicalEntry, context: harness.context, order: 0, weight: 135, reps: 8)
            try harness.context.save()

            let service = makeService(context: harness.context, user: user)
            guard let linearProfile = profile(named: "Load Progression", in: service) else {
                return fail("progression-test1", "Expected built-in Load Progression profile to exist")
            }

            let progressionExercise = service.assignProgression(to: exercise, profile: linearProfile)

            var ok = true
            ok = ok && check("progression-test1", service.profiles.count >= 3, "Expected built-in profiles to seed from JSON")
            ok = ok && check("progression-test1", progressionExercise?.workingWeight == 135, "Expected backfill to seed the most recent logged weight")
            ok = ok && check("progression-test1", progressionExercise?.workingWeightUnit == .lb, "Expected backfill to keep the source weight unit")
            ok = ok && check("progression-test1", progressionExercise?.hasBackfilled == true, "Expected assignment to record that backfill occurred")
            ok = ok && check("progression-test1", historicalEntry.hasProgressionSnapshot == false, "Expected backfill to leave historical session entries untouched")
            print("[progression-test1] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("progression-test1", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func test2LinearProgressionAdvancesAcrossSessionsAndIgnoresDuplicateEvaluation() -> Bool {
        do {
            let harness = try makeHarness()
            let user = User(name: "Linear User")
            harness.context.insert(user)

            let exercise = Exercise(name: "Incline Press", type: .weight, user_id: user.id)
            harness.context.insert(exercise)

            let seedSession = Session(timestamp: Date().addingTimeInterval(-7200), user_id: user.id, routine: nil, notes: "")
            seedSession.timestampDone = seedSession.timestamp.addingTimeInterval(300)
            harness.context.insert(seedSession)
            let seedEntry = SessionEntry(order: 0, session: seedSession, exercise: exercise)
            harness.context.insert(seedEntry)
            addStrengthSet(to: seedEntry, context: harness.context, order: 0, weight: 100, reps: 8)
            try harness.context.save()

            let service = makeService(context: harness.context, user: user)
            guard let linearProfile = profile(named: "Load Progression", in: service),
                  let progressionExercise = service.assignProgression(
                    to: exercise,
                    profile: linearProfile,
                    targetSets: 1,
                    targetReps: 8,
                    targetRepsLow: nil,
                    targetRepsHigh: nil
                  ) else {
                return fail("progression-test2", "Expected linear progression assignment to succeed")
            }

            let firstSession = Session(timestamp: Date().addingTimeInterval(-1800), user_id: user.id, routine: nil, notes: "")
            harness.context.insert(firstSession)
            let firstEntry = SessionEntry(order: 0, session: firstSession, exercise: exercise)
            harness.context.insert(firstEntry)
            addStrengthSet(to: firstEntry, context: harness.context, order: 0, weight: 100, reps: 8)
            _ = service.applySnapshot(to: firstEntry)
            firstSession.timestampDone = firstSession.timestamp.addingTimeInterval(120)
            try harness.context.save()
            service.evaluateIfNeeded(for: firstSession)

            let secondSession = Session(timestamp: Date(), user_id: user.id, routine: nil, notes: "")
            harness.context.insert(secondSession)
            let secondEntry = SessionEntry(order: 0, session: secondSession, exercise: exercise)
            harness.context.insert(secondEntry)
            addStrengthSet(to: secondEntry, context: harness.context, order: 0, weight: 105, reps: 8)
            _ = service.applySnapshot(to: secondEntry)
            secondSession.timestampDone = secondSession.timestamp.addingTimeInterval(120)
            try harness.context.save()
            service.evaluateIfNeeded(for: secondSession)

            let weightAfterSecondEvaluation = progressionExercise.workingWeight
            service.evaluateIfNeeded(for: secondSession)

            var ok = true
            ok = ok && check("progression-test2", firstEntry.appliedProgressionProfileId == linearProfile.id, "Expected session snapshots to store the resolved progression profile")
            ok = ok && check("progression-test2", firstEntry.appliedTargetReps == 8, "Expected the snapped target reps to remain on the completed session")
            ok = ok && check("progression-test2", progressionExercise.workingWeight == 110, "Expected linear progression to advance across multiple completed sessions")
            ok = ok && check("progression-test2", weightAfterSecondEvaluation == 110, "Expected the second completed session to produce the next weight")
            ok = ok && check("progression-test2", progressionExercise.lastEvaluatedSessionId == secondSession.id, "Expected the second session to be marked as evaluated")
            ok = ok && check("progression-test2", progressionExercise.workingWeight == weightAfterSecondEvaluation, "Expected duplicate evaluation of the same session not to advance again")
            print("[progression-test2] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("progression-test2", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func test3DoubleProgressionSuggestsRangeAndDoesNotStayStuck() -> Bool {
        do {
            let harness = try makeHarness()
            let user = User(name: "Double User")
            harness.context.insert(user)

            let exercise = Exercise(name: "Hack Squat", type: .weight, user_id: user.id)
            harness.context.insert(exercise)

            let historySession = Session(timestamp: Date().addingTimeInterval(-7200), user_id: user.id, routine: nil, notes: "")
            historySession.timestampDone = historySession.timestamp.addingTimeInterval(300)
            harness.context.insert(historySession)
            let historyEntry = SessionEntry(order: 0, session: historySession, exercise: exercise)
            harness.context.insert(historyEntry)
            addStrengthSet(to: historyEntry, context: harness.context, order: 0, weight: 235, reps: 10)
            try harness.context.save()

            let service = makeService(context: harness.context, user: user)
            guard let doubleProfile = profile(named: "Double Progression", in: service) else {
                return fail("progression-test3", "Expected built-in Double Progression profile to exist")
            }

            doubleProfile.percentageIncrease = 2.5

            guard let progressionExercise = service.assignProgression(
                to: exercise,
                profile: doubleProfile,
                targetSets: 1,
                targetReps: 12,
                targetRepsLow: 8,
                targetRepsHigh: 12
            ) else {
                return fail("progression-test3", "Expected double progression assignment to succeed")
            }

            progressionExercise.workingWeight = 240
            progressionExercise.workingWeightUnit = .lb
            try harness.context.save()

            let topRangeSession = Session(timestamp: Date().addingTimeInterval(-1800), user_id: user.id, routine: nil, notes: "")
            harness.context.insert(topRangeSession)
            let topRangeEntry = SessionEntry(order: 0, session: topRangeSession, exercise: exercise)
            harness.context.insert(topRangeEntry)
            addStrengthSet(to: topRangeEntry, context: harness.context, order: 0, weight: 240, reps: 12)
            _ = service.applySnapshot(to: topRangeEntry)
            topRangeSession.timestampDone = topRangeSession.timestamp.addingTimeInterval(240)
            try harness.context.save()
            service.evaluateIfNeeded(for: topRangeSession)

            let suggestionLow = progressionExercise.suggestedWeightLow
            let suggestionHigh = progressionExercise.suggestedWeightHigh

            let restartSession = Session(timestamp: Date(), user_id: user.id, routine: nil, notes: "")
            harness.context.insert(restartSession)
            let restartEntry = SessionEntry(order: 0, session: restartSession, exercise: exercise)
            harness.context.insert(restartEntry)
            addStrengthSet(to: restartEntry, context: harness.context, order: 0, weight: 245, reps: 8)
            _ = service.applySnapshot(to: restartEntry)
            restartSession.timestampDone = restartSession.timestamp.addingTimeInterval(240)
            try harness.context.save()
            service.evaluateIfNeeded(for: restartSession)

            var ok = true
            ok = ok && check("progression-test3", suggestionLow == 245, "Expected the least observed 5 lb increase to become the low suggestion")
            ok = ok && check("progression-test3", suggestionHigh == 246, "Expected the percentage-based increase to become the high suggestion")
            ok = ok && check("progression-test3", progressionExercise.lastCompletedCycleWeight == 240, "Expected the completed top-range weight to be remembered")
            ok = ok && check("progression-test3", progressionExercise.lastCompletedCycleReps == 12, "Expected the completed top-range reps to be remembered")
            ok = ok && check("progression-test3", progressionExercise.workingWeight == 245, "Expected logging the chosen restart weight to become the new working weight")
            ok = ok && check("progression-test3", progressionExercise.targetReps == 9, "Expected double progression to move to the next rep target after the restart session")
            ok = ok && check("progression-test3", progressionExercise.suggestedWeightLow == nil && progressionExercise.suggestedWeightHigh == nil, "Expected the suggested range to clear once a restart weight is actually used")
            print("[progression-test3] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("progression-test3", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func test4VolumeProgressionIncreasesSets() -> Bool {
        do {
            let harness = try makeHarness()
            let user = User(name: "Volume User")
            harness.context.insert(user)

            let exercise = Exercise(name: "Leg Extension", type: .weight, user_id: user.id)
            harness.context.insert(exercise)
            try harness.context.save()

            let service = makeService(context: harness.context, user: user)
            guard let volumeProfile = profile(named: "Volume Progression", in: service),
                  let progressionExercise = service.assignProgression(
                    to: exercise,
                    profile: volumeProfile,
                    targetSets: 3,
                    targetReps: 10,
                    targetRepsLow: nil,
                    targetRepsHigh: nil
                  ) else {
                return fail("progression-test4", "Expected volume progression assignment to succeed")
            }

            progressionExercise.workingWeight = 50
            progressionExercise.workingWeightUnit = .lb
            try harness.context.save()

            let session = Session(timestamp: Date(), user_id: user.id, routine: nil, notes: "")
            harness.context.insert(session)
            let entry = SessionEntry(order: 0, session: session, exercise: exercise)
            harness.context.insert(entry)
            addStrengthSet(to: entry, context: harness.context, order: 0, weight: 50, reps: 10)
            addStrengthSet(to: entry, context: harness.context, order: 1, weight: 50, reps: 10)
            addStrengthSet(to: entry, context: harness.context, order: 2, weight: 50, reps: 10)
            _ = service.applySnapshot(to: entry)
            session.timestampDone = session.timestamp.addingTimeInterval(180)
            try harness.context.save()
            service.evaluateIfNeeded(for: session)

            var ok = true
            ok = ok && check("progression-test4", progressionExercise.targetSetCount == 4, "Expected volume progression to add a set instead of load")
            ok = ok && check("progression-test4", progressionExercise.workingWeight == 50, "Expected volume progression to keep the working weight steady")
            print("[progression-test4] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("progression-test4", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func test5SourceResolutionUsesRoutineProgramAndUserFallback() -> Bool {
        do {
            let harness = try makeHarness()
            let user = User(name: "Source User")
            harness.context.insert(user)

            let exerciseRoutine = Exercise(name: "Routine Source", type: .weight, user_id: user.id)
            let exerciseProgram = Exercise(name: "Program Source", type: .weight, user_id: user.id)
            let exerciseFallback = Exercise(name: "Fallback Source", type: .weight, user_id: user.id)
            harness.context.insert(exerciseRoutine)
            harness.context.insert(exerciseProgram)
            harness.context.insert(exerciseFallback)
            try harness.context.save()

            let service = makeService(context: harness.context, user: user)
            guard let linearProfile = profile(named: "Load Progression", in: service),
                  let doubleProfile = profile(named: "Double Progression", in: service),
                  let volumeProfile = profile(named: "Volume Progression", in: service) else {
                return fail("progression-test5", "Expected all built-in profiles to exist")
            }

            user.globalProgressionEnabled = true
            user.defaultProgressionProfileId = volumeProfile.id

            let routineSource = makeRoutine(name: "Routine Source Plan", user: user, exercise: exerciseRoutine, context: harness.context)
            routineSource.defaultProgressionProfileId = linearProfile.id

            let routineInProgram = makeRoutine(name: "Program Source Plan", user: user, exercise: exerciseProgram, context: harness.context)
            routineInProgram.defaultProgressionProfileId = linearProfile.id

            let fallbackRoutine = makeRoutine(name: "Fallback Plan", user: user, exercise: exerciseFallback, context: harness.context)
            fallbackRoutine.defaultProgressionProfileId = linearProfile.id

            let programService = ProgramService(context: harness.context)
            programService.currentUser = user
            let sessionRepository = LocalSessionRepository(modelContext: harness.context)

            guard let programWithDefault = programService.createProgram(name: "Program Default", mode: .continuous, startDate: Date()),
                  let programWithDefaultBlock = programService.directWorkoutBlock(for: programWithDefault),
                  let programWithDefaultWorkout = programService.addWorkout(to: programWithDefaultBlock, routine: routineInProgram, name: nil, weekdayIndex: nil),
                  let programWithoutDefault = programService.createProgram(name: "Program Fallback", mode: .continuous, startDate: Date()),
                  let programWithoutDefaultBlock = programService.directWorkoutBlock(for: programWithoutDefault),
                  let programWithoutDefaultWorkout = programService.addWorkout(to: programWithoutDefaultBlock, routine: fallbackRoutine, name: nil, weekdayIndex: nil) else {
                return fail("progression-test5", "Expected source-resolution programs to be created")
            }

            programWithDefault.defaultProgressionProfileId = doubleProfile.id
            try harness.context.save()

            let routineSession = try sessionRepository.createSession(userId: user.id, routine: routineSource, notes: "")
            let programSession = try sessionRepository.createProgramSession(
                userId: user.id,
                program: programWithDefault,
                programBlock: programWithDefaultBlock,
                programWorkout: programWithDefaultWorkout,
                notes: "",
                programWeekIndex: nil,
                programSplitIndex: 1
            )
            let fallbackProgramSession = try sessionRepository.createProgramSession(
                userId: user.id,
                program: programWithoutDefault,
                programBlock: programWithoutDefaultBlock,
                programWorkout: programWithoutDefaultWorkout,
                notes: "",
                programWeekIndex: nil,
                programSplitIndex: 1
            )

            guard let routineEntry = routineSession.sessionEntries.first,
                  let programEntry = programSession.sessionEntries.first,
                  let fallbackEntry = fallbackProgramSession.sessionEntries.first else {
                return fail("progression-test5", "Expected created sessions to contain entries")
            }

            _ = service.applySnapshot(to: routineEntry)
            _ = service.applySnapshot(to: programEntry)
            _ = service.applySnapshot(to: fallbackEntry)
            service.loadProgressionExercises()

            var ok = true
            ok = ok && check("progression-test5", routineEntry.appliedProgressionProfileId == linearProfile.id, "Expected direct routine sessions to use the routine default")
            ok = ok && check("progression-test5", service.progressionExercise(for: exerciseRoutine.id)?.assignmentSource == .routineDefault, "Expected routine default progression rows to be marked as inherited from the routine")
            ok = ok && check("progression-test5", programEntry.appliedProgressionProfileId == doubleProfile.id, "Expected program-started sessions to use the program default")
            ok = ok && check("progression-test5", service.progressionExercise(for: exerciseProgram.id)?.assignmentSource == .programDefault, "Expected program default progression rows to be marked as inherited from the program")
            ok = ok && check("progression-test5", fallbackEntry.appliedProgressionProfileId == volumeProfile.id, "Expected program sessions without a program default to fall back to the user default instead of the routine default")
            ok = ok && check("progression-test5", service.progressionExercise(for: exerciseFallback.id)?.assignmentSource == .userDefault, "Expected fallback progression rows to be marked as inherited from the global default")
            print("[progression-test5] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("progression-test5", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func test6ExplicitOverrideBeatsInheritedDefaults() -> Bool {
        do {
            let harness = try makeHarness()
            let user = User(name: "Override User")
            harness.context.insert(user)

            let exercise = Exercise(name: "Override Exercise", type: .weight, user_id: user.id)
            harness.context.insert(exercise)
            try harness.context.save()

            let service = makeService(context: harness.context, user: user)
            guard let linearProfile = profile(named: "Load Progression", in: service),
                  let doubleProfile = profile(named: "Double Progression", in: service),
                  let volumeProfile = profile(named: "Volume Progression", in: service) else {
                return fail("progression-test6", "Expected built-in profiles to exist")
            }

            user.globalProgressionEnabled = true
            user.defaultProgressionProfileId = volumeProfile.id

            let routine = makeRoutine(name: "Override Routine", user: user, exercise: exercise, context: harness.context)
            routine.defaultProgressionProfileId = linearProfile.id
            try harness.context.save()

            guard let override = service.assignProgression(
                to: exercise,
                profile: doubleProfile,
                targetSets: 3,
                targetReps: nil,
                targetRepsLow: 8,
                targetRepsHigh: 12
            ) else {
                return fail("progression-test6", "Expected explicit exercise override assignment to succeed")
            }

            let sessionRepository = LocalSessionRepository(modelContext: harness.context)
            let session = try sessionRepository.createSession(userId: user.id, routine: routine, notes: "")
            guard let entry = session.sessionEntries.first else {
                return fail("progression-test6", "Expected override test session to contain an entry")
            }

            _ = service.applySnapshot(to: entry)
            service.loadProgressionExercises()

            var ok = true
            ok = ok && check("progression-test6", override.assignmentSource == .exerciseOverride, "Expected saved exercise progression to remain an explicit override")
            ok = ok && check("progression-test6", service.exerciseOverride(for: exercise.id)?.progressionProfileId == doubleProfile.id, "Expected inherited defaults not to overwrite the explicit exercise override")
            ok = ok && check("progression-test6", entry.appliedProgressionProfileId == doubleProfile.id, "Expected the explicit exercise override to win over routine and user defaults")
            print("[progression-test6] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("progression-test6", "Unexpected error: \(error)")
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
            ProgramWorkout.self,
            ProgressionProfile.self,
            ProgressionExercise.self
        ])

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        return Harness(container: container, context: context)
    }

    private static func makeService(context: ModelContext, user: User) -> ProgressionService {
        let service = ProgressionService(context: context)
        service.currentUser = user
        service.loadFeature()
        return service
    }

    private static func profile(named name: String, in service: ProgressionService) -> ProgressionProfile? {
        service.profiles.first(where: { $0.name == name })
    }

    @discardableResult
    private static func makeRoutine(name: String, user: User, exercise: Exercise, context: ModelContext) -> Routine {
        let routine = Routine(order: 0, name: name, user_id: user.id)
        context.insert(routine)
        let split = ExerciseSplitDay(order: 0, routine: routine, exercise: exercise)
        context.insert(split)
        routine.exerciseSplits.append(split)
        return routine
    }

    private static func addStrengthSet(
        to entry: SessionEntry,
        context: ModelContext,
        order: Int,
        weight: Double,
        reps: Int,
        unit: WeightUnit = .lb
    ) {
        let set = SessionSet(order: order, sessionEntry: entry)
        context.insert(set)
        let rep = SessionRep(sessionSet: set, weight: weight, weight_unit: unit, count: reps)
        context.insert(rep)
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
