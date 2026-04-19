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
            test1BuiltInSeedAndBackfillUsesRecentHistory(),
            test2EvaluationAdvancesOnlyOncePerSession()
        ]
        let passCount = results.filter { $0 }.count
        print("=== ProgressionFeatureDebug done: \(passCount)/\(results.count) passed ===")
    }

    @discardableResult
    private static func test1BuiltInSeedAndBackfillUsesRecentHistory() -> Bool {
        do {
            let harness = try makeHarness()
            let user = User(name: "Progression User")
            harness.context.insert(user)

            let exercise = Exercise(name: "Bench Press", type: .weight, user_id: user.id)
            harness.context.insert(exercise)

            let session = Session(timestamp: Date(), user_id: user.id, routine: nil, notes: "")
            harness.context.insert(session)
            let entry = SessionEntry(order: 0, session: session, exercise: exercise)
            harness.context.insert(entry)
            let set = SessionSet(order: 0, sessionEntry: entry)
            harness.context.insert(set)
            let rep = SessionRep(sessionSet: set, weight: 135, weight_unit: .lb, count: 8)
            harness.context.insert(rep)
            try harness.context.save()

            let service = ProgressionService(context: harness.context)
            service.currentUser = user
            service.loadFeature()

            guard let linearProfile = service.profiles.first(where: { $0.name == "Load Progression" }) else {
                return fail("progression-test1", "Expected built-in Load Progression profile to seed from JSON")
            }

            let progressionExercise = service.assignProgression(to: exercise, profile: linearProfile)

            var ok = true
            ok = ok && check("progression-test1", progressionExercise != nil, "Expected progression exercise assignment")
            ok = ok && check("progression-test1", service.profiles.count >= 3, "Expected at least the three default profiles to load")
            ok = ok && check("progression-test1", progressionExercise?.workingWeight == 135, "Expected backfill to use the most recent logged weight")
            ok = ok && check("progression-test1", progressionExercise?.workingWeightUnit == .lb, "Expected backfill to keep the source unit")
            ok = ok && check("progression-test1", progressionExercise?.hasBackfilled == true, "Expected assignment to record that backfill occurred")
            print("[progression-test1] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("progression-test1", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func test2EvaluationAdvancesOnlyOncePerSession() -> Bool {
        do {
            let harness = try makeHarness()
            let user = User(name: "Evaluation User")
            harness.context.insert(user)

            let exercise = Exercise(name: "Incline Press", type: .weight, user_id: user.id)
            harness.context.insert(exercise)
            try harness.context.save()

            let service = ProgressionService(context: harness.context)
            service.currentUser = user
            service.loadFeature()

            guard let linearProfile = service.profiles.first(where: { $0.name == "Load Progression" }) else {
                return fail("progression-test2", "Expected built-in Load Progression profile to exist")
            }

            guard let progressionExercise = service.assignProgression(
                to: exercise,
                profile: linearProfile,
                targetSets: 1,
                targetReps: 8,
                targetRepsLow: nil,
                targetRepsHigh: nil
            ) else {
                return fail("progression-test2", "Expected progression assignment to succeed")
            }

            let session = Session(timestamp: Date(), user_id: user.id, routine: nil, notes: "")
            harness.context.insert(session)
            let entry = SessionEntry(order: 0, session: session, exercise: exercise)
            harness.context.insert(entry)
            let set = SessionSet(order: 0, sessionEntry: entry)
            harness.context.insert(set)
            let rep = SessionRep(sessionSet: set, weight: 100, weight_unit: .lb, count: 8)
            harness.context.insert(rep)
            try harness.context.save()

            _ = service.applySnapshot(to: entry)
            session.timestampDone = session.timestamp.addingTimeInterval(120)
            service.evaluateIfNeeded(for: session)

            let weightAfterFirstEvaluation = progressionExercise.workingWeight
            let lastEvaluatedSessionId = progressionExercise.lastEvaluatedSessionId

            service.evaluateIfNeeded(for: session)

            var ok = true
            ok = ok && check("progression-test2", weightAfterFirstEvaluation == 105, "Expected linear progression to add the default 5 lb increment once")
            ok = ok && check("progression-test2", progressionExercise.workingWeight == weightAfterFirstEvaluation, "Expected a second evaluation call to be ignored for the same session")
            ok = ok && check("progression-test2", progressionExercise.lastEvaluatedSessionId == lastEvaluatedSessionId, "Expected duplicate evaluations to leave the evaluation marker unchanged")
            ok = ok && check("progression-test2", progressionExercise.successCount == 0, "Expected the success counter to reset after advancing")
            print("[progression-test2] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("progression-test2", "Unexpected error: \(error)")
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
            ProgressionProfile.self,
            ProgressionExercise.self
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
