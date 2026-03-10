#if DEBUG
import Foundation
import SwiftData

final class ExerciseMergeDebug {
    private static var hasRun = false

    static func runSamples() {
        guard !hasRun else { return }
        hasRun = true

        print("=== ExerciseMergeDebug start ===")
        let results = [
            test1MergeRelinksReferencesAndDeletesDuplicate()
        ]
        let passCount = results.filter { $0 }.count
        print("=== ExerciseMergeDebug done: \(passCount)/\(results.count) passed ===")
    }

    @discardableResult
    private static func test1MergeRelinksReferencesAndDeletesDuplicate() -> Bool {
        do {
            let harness = try makeHarness()
            let currentUser = User(name: "Current")
            let otherUser = User(name: "Other")
            harness.context.insert(currentUser)
            harness.context.insert(otherUser)

            let primary = Exercise(name: "Alternate Hammer Curl", type: .weight, user_id: currentUser.id)
            primary.npId = "alternate-hammer-curl"
            primary.aliases = ["Alt Hammer Curl"]

            let duplicate = Exercise(name: "Hammer curls alternating standing", type: .weight, user_id: otherUser.id)
            duplicate.npId = "alternate-hammer-curl"
            duplicate.aliases = ["Hammer curls alternating standing"]

            harness.context.insert(primary)
            harness.context.insert(duplicate)

            let routine = Routine(order: 0, name: "Pull", user_id: otherUser.id)
            harness.context.insert(routine)
            let split = ExerciseSplitDay(order: 0, routine: routine, exercise: duplicate)
            harness.context.insert(split)

            let session = Session(timestamp: Date(), user_id: otherUser.id, routine: routine, notes: "")
            harness.context.insert(session)
            let entry = SessionEntry(order: 0, session: session, exercise: duplicate)
            harness.context.insert(entry)
            let set = SessionSet(order: 0, sessionEntry: entry)
            harness.context.insert(set)
            let rep = SessionRep(sessionSet: set, weight: 40, weight_unit: .lb, count: 10)
            harness.context.insert(rep)

            try harness.context.save()

            let service = ExerciseService(context: harness.context)
            service.currentUser = currentUser

            let report = try service.mergeExercisesWithSameNpId()

            var ok = true
            ok = ok && check("merge-test1", report.groupsMerged == 1, "Expected one merged npId group")
            ok = ok && check("merge-test1", report.duplicatesRemoved == 1, "Expected one duplicate removal")
            ok = ok && check("merge-test1", split.exercise.id == primary.id, "Expected routine split to point to primary")
            ok = ok && check("merge-test1", entry.exercise.id == primary.id, "Expected session entry to point to primary")
            ok = ok && check("merge-test1", session.user_id == currentUser.id, "Expected session ownership moved to current user")
            ok = ok && check("merge-test1", routine.user_id == currentUser.id, "Expected routine ownership moved to current user")
            let entryId = entry.id
            let setId = set.id
            let setFetch = FetchDescriptor<SessionSet>(
                predicate: #Predicate<SessionSet> { sessionSet in
                    sessionSet.sessionEntry.id == entryId
                }
            )
            let repFetch = FetchDescriptor<SessionRep>(
                predicate: #Predicate<SessionRep> { sessionRep in
                    sessionRep.sessionSet.id == setId
                }
            )
            let persistedSets = try harness.context.fetch(setFetch)
            let persistedReps = try harness.context.fetch(repFetch)
            ok = ok && check("merge-test1", persistedSets.count == 1 && persistedReps.count == 1, "Expected set/rep chain preserved")

            let duplicateId = duplicate.id
            let duplicateFetch = FetchDescriptor<Exercise>(
                predicate: #Predicate<Exercise> { exercise in
                    exercise.id == duplicateId
                }
            )
            let duplicateStillExists = try !harness.context.fetch(duplicateFetch).isEmpty
            ok = ok && check("merge-test1", !duplicateStillExists, "Expected duplicate exercise deleted")

            print("[merge-test1] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("merge-test1", "Unexpected error: \(error)")
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
            SessionRep.self
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
