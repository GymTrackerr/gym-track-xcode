#if DEBUG
import Foundation
import SwiftData

final class ExerciseBackupDebug {
    private static var hasRun = false

    static func runSamples() {
        guard !hasRun else { return }
        hasRun = true

        print("=== ExerciseBackupDebug start ===")
        let results = [
            test1ExportSkipsNonUserExercisesAndKeepsNpIdReferences(),
            test2ImportLinksByNpIdToExistingExercise()
        ]
        let passCount = results.filter { $0 }.count
        print("=== ExerciseBackupDebug done: \(passCount)/\(results.count) passed ===")
    }

    @discardableResult
    private static func test1ExportSkipsNonUserExercisesAndKeepsNpIdReferences() -> Bool {
        do {
            let fixture = try makeExportFixture()
            let data = try Data(contentsOf: fixture.exportURL)
            guard
                let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let payload = root["payload"] as? [String: Any],
                let exercises = payload["exercises"] as? [[String: Any]],
                let splitDays = payload["splitDays"] as? [[String: Any]],
                let entries = payload["sessionEntries"] as? [[String: Any]]
            else {
                return fail("backup-test1", "Could not parse export JSON")
            }

            var ok = true
            ok = ok && check("backup-test1", exercises.count == 1, "Expected only user-created exercise in payload.exercises")
            let allUserCreated = exercises.allSatisfy { ($0["isUserCreated"] as? Bool) == true }
            ok = ok && check("backup-test1", allUserCreated, "Expected every exported exercise to be user-created")
            let splitHasNpId = splitDays.contains { ($0["exerciseNpId"] as? String) == fixture.apiExerciseNpId }
            let entryHasNpId = entries.contains { ($0["exerciseNpId"] as? String) == fixture.apiExerciseNpId }
            ok = ok && check("backup-test1", splitHasNpId, "Expected split day to include API exercise npId reference")
            ok = ok && check("backup-test1", entryHasNpId, "Expected session entry to include API exercise npId reference")

            print("[backup-test1] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("backup-test1", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func test2ImportLinksByNpIdToExistingExercise() -> Bool {
        do {
            let fixture = try makeExportFixture()
            let data = try Data(contentsOf: fixture.exportURL)

            let targetHarness = try makeHarness()
            let targetUser = User(name: "Import Target")
            targetHarness.context.insert(targetUser)

            let existingApiExercise = Exercise(name: "API Existing", type: .weight, user_id: targetUser.id, isUserCreated: false)
            existingApiExercise.npId = fixture.apiExerciseNpId
            targetHarness.context.insert(existingApiExercise)
            try targetHarness.context.save()

            let service = ExerciseBackupService(
                context: targetHarness.context,
                currentUserProvider: { targetUser }
            )
            _ = try service.importExercises(data: data, mode: .merge)

            let splitDescriptor = FetchDescriptor<ExerciseSplitDay>()
            let entryDescriptor = FetchDescriptor<SessionEntry>()
            let splits = try targetHarness.context.fetch(splitDescriptor)
            let entries = try targetHarness.context.fetch(entryDescriptor)

            var ok = true
            ok = ok && check("backup-test2", !splits.isEmpty, "Expected imported split days")
            ok = ok && check("backup-test2", !entries.isEmpty, "Expected imported session entries")
            if let split = splits.first {
                ok = ok && check("backup-test2", split.exercise.id == existingApiExercise.id, "Expected split linked to existing npId-matched exercise")
            }
            if let entry = entries.first {
                ok = ok && check("backup-test2", entry.exercise.id == existingApiExercise.id, "Expected entry linked to existing npId-matched exercise")
            }

            print("[backup-test2] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("backup-test2", "Unexpected error: \(error)")
        }
    }

    private struct Harness {
        let container: ModelContainer
        let context: ModelContext
    }

    private struct ExportFixture {
        let exportURL: URL
        let apiExerciseNpId: String
    }

    private static func makeExportFixture() throws -> ExportFixture {
        let harness = try makeHarness()
        let user = User(name: "Exporter")
        harness.context.insert(user)

        let apiExercise = Exercise(name: "Alternate Hammer Curl", type: .weight, user_id: user.id, isUserCreated: false)
        apiExercise.npId = "alternate-hammer-curl"

        let userExercise = Exercise(name: "My Custom Curl", type: .weight, user_id: user.id, isUserCreated: true)
        userExercise.npId = "my-custom-curl"

        harness.context.insert(apiExercise)
        harness.context.insert(userExercise)

        let routine = Routine(order: 0, name: "Pull", user_id: user.id)
        harness.context.insert(routine)
        harness.context.insert(ExerciseSplitDay(order: 0, routine: routine, exercise: apiExercise))

        let session = Session(timestamp: Date(), user_id: user.id, routine: routine, notes: "")
        harness.context.insert(session)
        harness.context.insert(SessionEntry(order: 0, session: session, exercise: apiExercise))

        try harness.context.save()

        let service = ExerciseBackupService(
            context: harness.context,
            currentUserProvider: { user }
        )
        let exportURL = try service.exportExercisesJSON()
        return ExportFixture(exportURL: exportURL, apiExerciseNpId: apiExercise.npId ?? "")
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
