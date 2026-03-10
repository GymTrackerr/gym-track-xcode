#if DEBUG
import Foundation
import SwiftData

final class SessionExerciseTransferDebug {
    private static var hasRun = false

    static func runSamples() {
        guard !hasRun else { return }
        hasRun = true

        print("=== SessionExerciseTransferDebug start ===")
        let results = [
            test1TransferPreservesSetsRepsAndCompletion()
        ]
        let passCount = results.filter { $0 }.count
        print("=== SessionExerciseTransferDebug done: \(passCount)/\(results.count) passed ===")
    }

    @discardableResult
    private static func test1TransferPreservesSetsRepsAndCompletion() -> Bool {
        do {
            let harness = try makeHarness()
            let user = User(name: "Transfer User")
            harness.context.insert(user)

            let source = Exercise(name: "Source Exercise", type: .weight, user_id: user.id)
            let target = Exercise(name: "Target Exercise", type: .weight, user_id: user.id)
            harness.context.insert(source)
            harness.context.insert(target)

            let session = Session(timestamp: Date(), user_id: user.id, routine: nil, notes: "")
            harness.context.insert(session)

            let sourceEntry = SessionEntry(order: 0, session: session, exercise: source)
            harness.context.insert(sourceEntry)

            let set1 = SessionSet(order: 0, sessionEntry: sourceEntry, notes: "set-1")
            set1.isCompleted = true
            harness.context.insert(set1)

            let set2 = SessionSet(order: 1, sessionEntry: sourceEntry, notes: "set-2")
            set2.isCompleted = false
            harness.context.insert(set2)

            let rep1 = SessionRep(sessionSet: set1, weight: 100, weight_unit: .lb, count: 5)
            let rep2 = SessionRep(sessionSet: set2, weight: 90, weight_unit: .lb, count: 8)
            harness.context.insert(rep1)
            harness.context.insert(rep2)

            try harness.context.save()

            // Perform transfer (now just updates exercise reference)
            let service = SessionExerciseService(context: harness.context)
            try service.transferExerciseHistory(from: source, to: target, sessionIds: [session.id])

            let entries = try harness.context.fetch(FetchDescriptor<SessionEntry>())
            let reps = try harness.context.fetch(FetchDescriptor<SessionRep>())

            // After transfer, the source entry now points to target exercise
            let targetEntries = entries.filter { $0.exercise.id == target.id }
            let sets = try harness.context.fetch(FetchDescriptor<SessionSet>())

            var ok = true
            ok = ok && check("transfer-test1", targetEntries.count == 1, "Expected source entry now references target exercise")
            ok = ok && check("transfer-test1", sets.count == 2, "Expected both sets preserved")
            ok = ok && check("transfer-test1", reps.count == 2, "Expected reps preserved")

            let completionFlags = sets.map(\.isCompleted).sorted { lhs, rhs in
                (lhs ? 1 : 0) > (rhs ? 1 : 0)
            }
            ok = ok && check("transfer-test1", completionFlags == [true, false], "Expected set completion flags preserved")

            if let targetEntry = targetEntries.first {
                ok = ok && check("transfer-test1", targetEntry.isCompleted == false, "Expected entry completion matches sets")
            }

            let movedNotes = Set(sets.compactMap(\.notes))
            ok = ok && check("transfer-test1", movedNotes == Set(["set-1", "set-2"]), "Expected set notes preserved")

            print("[transfer-test1] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("transfer-test1", "Unexpected error: \(error)")
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
