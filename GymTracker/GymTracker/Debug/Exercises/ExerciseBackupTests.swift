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
            test2ImportLinksByNpIdToExistingExercise(),
            test3NpExerciseAliasJoinExportAndMerge(),
            test4LegacyImportAllowsMissingProgramsAndRoutines(),
            test5ProgramAndProgressionRoundTrip(),
            test6RoutineSplitSnapshotReplacesStaleSplitDaysOnMerge()
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

    @discardableResult
    private static func test3NpExerciseAliasJoinExportAndMerge() -> Bool {
        do {
            let fixture = try makeExportFixture()
            let data = try Data(contentsOf: fixture.exportURL)

            guard
                let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let payload = root["payload"] as? [String: Any],
                let npExports = payload["npExerciseExports"] as? [[String: Any]]
            else {
                return fail("backup-test3", "Could not parse npExerciseExports in export JSON")
            }

            let matchingNpExport = npExports.first { ($0["npId"] as? String) == fixture.apiExerciseNpId }
            var ok = true
            ok = ok && check("backup-test3", matchingNpExport != nil, "Expected npExerciseExports entry for API npId")

            let targetHarness = try makeHarness()
            let targetUser = User(name: "Import Alias Target")
            targetHarness.context.insert(targetUser)

            let existingApiExercise = Exercise(name: "API Existing", type: .weight, user_id: targetUser.id, isUserCreated: false)
            existingApiExercise.npId = fixture.apiExerciseNpId
            existingApiExercise.aliases = ["alt hammer curl", "Extra Existing Alias"]
            targetHarness.context.insert(existingApiExercise)
            try targetHarness.context.save()

            let service = ExerciseBackupService(
                context: targetHarness.context,
                currentUserProvider: { targetUser }
            )
            _ = try service.importExercises(data: data, mode: .merge)

            let descriptor = FetchDescriptor<Exercise>()
            let importedExercises = try targetHarness.context.fetch(descriptor).filter { exercise in
                exercise.user_id == targetUser.id
            }
            guard let resolved = importedExercises.first(where: {
                ($0.npId?.lowercased() ?? "") == fixture.apiExerciseNpId.lowercased()
            }) else {
                return fail("backup-test3", "Expected imported npId exercise to exist")
            }

            let aliases = resolved.aliases ?? []
            let lowerAliases = Set(aliases.map { $0.lowercased() })

            ok = ok && check("backup-test3", lowerAliases.contains("alternate hammer curl"), "Expected imported alias to be merged")
            ok = ok && check("backup-test3", lowerAliases.contains("extra existing alias"), "Expected existing alias to be preserved")
            ok = ok && check("backup-test3", lowerAliases.filter { $0 == "alt hammer curl" }.count == 1, "Expected case-insensitive dedupe for existing/imported alias")

            print("[backup-test3] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("backup-test3", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func test4LegacyImportAllowsMissingProgramsAndRoutines() -> Bool {
        do {
            let harness = try makeHarness()
            let user = User(name: "Legacy Target")
            harness.context.insert(user)
            try harness.context.save()

            let formatter = ISO8601DateFormatter()
            let timestamp = formatter.string(from: Date())
            let exerciseId = UUID()
            let sessionId = UUID()
            let entryId = UUID()

            let payload: [String: Any] = [
                "schemaVersion": 2,
                "exportedAt": timestamp,
                "userId": UUID().uuidString,
                "payload": [
                    "exercises": [
                        [
                            "id": exerciseId.uuidString,
                            "name": "Legacy Curl",
                            "userId": UUID().uuidString,
                            "isUserCreated": true,
                            "timestamp": timestamp
                        ]
                    ],
                    "sessions": [
                        [
                            "id": sessionId.uuidString,
                            "userId": UUID().uuidString,
                            "timestamp": timestamp,
                            "timestampDone": timestamp,
                            "notes": "Legacy session"
                        ]
                    ],
                    "sessionEntries": [
                        [
                            "id": entryId.uuidString,
                            "order": 0,
                            "isCompleted": false,
                            "sessionId": sessionId.uuidString,
                            "exerciseId": exerciseId.uuidString
                        ]
                    ]
                ]
            ]

            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            let service = ExerciseBackupService(
                context: harness.context,
                currentUserProvider: { user }
            )

            let report = try service.importExercises(data: data, mode: .merge)
            let exercises = try harness.context.fetch(FetchDescriptor<Exercise>())
            let sessions = try harness.context.fetch(FetchDescriptor<Session>())
            let entries = try harness.context.fetch(FetchDescriptor<SessionEntry>())

            var ok = true
            ok = ok && check("backup-test4", report.exercises.inserted == 1, "Expected one exercise inserted from legacy payload")
            ok = ok && check("backup-test4", exercises.count == 1, "Expected one imported exercise")
            ok = ok && check("backup-test4", sessions.count == 1, "Expected one imported session without routines")
            ok = ok && check("backup-test4", entries.count == 1, "Expected one imported entry without routines")
            ok = ok && check("backup-test4", sessions.first?.routine == nil, "Expected legacy session to import without routine link")

            print("[backup-test4] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("backup-test4", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func test5ProgramAndProgressionRoundTrip() -> Bool {
        do {
            let fixture = try makeRichExportFixture()
            let data = try Data(contentsOf: fixture.exportURL)

            let targetHarness = try makeHarness()
            let targetUser = User(name: "Round Trip Target")
            targetHarness.context.insert(targetUser)
            try targetHarness.context.save()

            let service = ExerciseBackupService(
                context: targetHarness.context,
                currentUserProvider: { targetUser }
            )
            let report = try service.importExercises(data: data, mode: .merge)

            let programs = try targetHarness.context.fetch(FetchDescriptor<Program>())
            let workouts = try targetHarness.context.fetch(FetchDescriptor<ProgramWorkout>())
            let profiles = try targetHarness.context.fetch(FetchDescriptor<ProgressionProfile>())
            let progressionExercises = try targetHarness.context.fetch(FetchDescriptor<ProgressionExercise>())
            let sessions = try targetHarness.context.fetch(FetchDescriptor<Session>())
            let entries = try targetHarness.context.fetch(FetchDescriptor<SessionEntry>())

            var ok = true
            ok = ok && check("backup-test5", report.programs.inserted == 1, "Expected one imported program")
            ok = ok && check("backup-test5", report.progressionProfiles.inserted == 1, "Expected one imported progression profile")
            ok = ok && check("backup-test5", report.progressionExercises.inserted == 1, "Expected one imported progression exercise")
            ok = ok && check("backup-test5", programs.count == 1, "Expected one imported program")
            ok = ok && check("backup-test5", workouts.count == 1, "Expected one imported program workout")
            ok = ok && check("backup-test5", profiles.count == 1, "Expected one imported progression profile")
            ok = ok && check("backup-test5", progressionExercises.count == 1, "Expected one imported progression exercise")
            ok = ok && check("backup-test5", targetUser.globalProgressionEnabled, "Expected global progression toggle to round-trip")
            ok = ok && check("backup-test5", targetUser.defaultProgressionProfileId == fixture.profileId, "Expected global default progression id to round-trip")
            ok = ok && check("backup-test5", sessions.first?.program?.id == programs.first?.id, "Expected imported session to link back to imported program")
            ok = ok && check("backup-test5", entries.first?.appliedProgressionProfileId == fixture.profileId, "Expected session entry progression snapshot to round-trip")

            print("[backup-test5] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("backup-test5", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func test6RoutineSplitSnapshotReplacesStaleSplitDaysOnMerge() -> Bool {
        do {
            let fixture = try makeExportFixture()
            let data = try Data(contentsOf: fixture.exportURL)

            guard
                let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let payload = root["payload"] as? [String: Any],
                let routines = payload["routines"] as? [[String: Any]],
                let firstRoutine = routines.first,
                let splitSnapshot = firstRoutine["splitDaySnapshot"] as? [[String: Any]],
                splitSnapshot.count == 1
            else {
                return fail("backup-test6", "Expected exported routine split snapshot")
            }

            let expectedSplitId = splitSnapshot.first?["id"] as? String

            let targetHarness = try makeHarness()
            let targetUser = User(name: "Split Snapshot Target")
            targetHarness.context.insert(targetUser)
            try targetHarness.context.save()

            let service = ExerciseBackupService(
                context: targetHarness.context,
                currentUserProvider: { targetUser }
            )

            _ = try service.importExercises(data: data, mode: .merge)

            let importedRoutines = try targetHarness.context.fetch(FetchDescriptor<Routine>())
            guard let importedRoutine = importedRoutines.first else {
                return fail("backup-test6", "Expected imported routine before stale split injection")
            }

            let staleExercise = Exercise(name: "Stale Extra Exercise", type: .weight, user_id: targetUser.id, isUserCreated: true)
            targetHarness.context.insert(staleExercise)

            let staleSplit = ExerciseSplitDay(order: 99, routine: importedRoutine, exercise: staleExercise)
            targetHarness.context.insert(staleSplit)
            importedRoutine.exerciseSplits.append(staleSplit)
            try targetHarness.context.save()

            _ = try service.importExercises(data: data, mode: .merge)

            let splitDays = try targetHarness.context.fetch(FetchDescriptor<ExerciseSplitDay>())
            let routineSplitDays = splitDays
                .filter { $0.routine.id == importedRoutine.id }
                .sorted { $0.order < $1.order }

            var ok = true
            ok = ok && check("backup-test6", routineSplitDays.count == 1, "Expected merge import to prune stale routine split days")
            ok = ok && check("backup-test6", routineSplitDays.first?.id.uuidString == expectedSplitId, "Expected routine split snapshot id to be preserved")
            ok = ok && check("backup-test6", routineSplitDays.first?.exercise.npId == fixture.apiExerciseNpId, "Expected authoritative split snapshot exercise after reimport")

            print("[backup-test6] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("backup-test6", "Unexpected error: \(error)")
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

    private struct RichExportFixture {
        let exportURL: URL
        let profileId: UUID
    }

    private static func makeExportFixture() throws -> ExportFixture {
        let harness = try makeHarness()
        let user = User(name: "Exporter")
        harness.context.insert(user)

        let apiExercise = Exercise(name: "Alternate Hammer Curl", type: .weight, user_id: user.id, isUserCreated: false)
        apiExercise.npId = "alternate-hammer-curl"
        apiExercise.aliases = ["Alternate Hammer Curl", "Alt Hammer Curl"]

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

    private static func makeRichExportFixture() throws -> RichExportFixture {
        let harness = try makeHarness()
        let user = User(name: "Rich Exporter")
        harness.context.insert(user)

        let exercise = Exercise(name: "Paused Bench", type: .weight, user_id: user.id, isUserCreated: true)
        harness.context.insert(exercise)

        let routine = Routine(order: 0, name: "Upper A", user_id: user.id)
        harness.context.insert(routine)
        harness.context.insert(ExerciseSplitDay(order: 0, routine: routine, exercise: exercise))

        let profile = ProgressionProfile(
            userId: user.id,
            name: "Custom Double",
            miniDescription: "Build reps before load.",
            type: .doubleProgression,
            incrementValue: 5,
            percentageIncrease: 0,
            incrementUnit: .lb,
            setIncrement: 1,
            successThreshold: 1,
            defaultSetsTarget: 3,
            defaultRepsTarget: 8,
            defaultRepsLow: 8,
            defaultRepsHigh: 12,
            isBuiltIn: false
        )
        harness.context.insert(profile)

        user.globalProgressionEnabled = true
        user.defaultProgressionProfileId = profile.id
        routine.defaultProgressionProfileId = profile.id
        routine.defaultProgressionProfileNameSnapshot = profile.name

        let program = Program(userId: user.id, name: "Strength Block", notes: "", mode: .weekly)
        program.defaultProgressionProfileId = profile.id
        program.defaultProgressionProfileNameSnapshot = profile.name
        harness.context.insert(program)

        let block = ProgramBlock(order: 0, program: program, name: "Block 1", durationCount: 4)
        harness.context.insert(block)

        let workout = ProgramWorkout(order: 0, programBlock: block, routine: routine, name: "Day 1", weekdayIndex: ProgramWeekday.monday.rawValue)
        harness.context.insert(workout)

        let progressionExercise = ProgressionExercise(
            userId: user.id,
            exerciseId: exercise.id,
            exerciseName: exercise.name,
            profile: profile,
            targetSetCount: 3,
            targetReps: 8,
            targetRepsLow: 8,
            targetRepsHigh: 12
        )
        progressionExercise.workingWeight = 225
        progressionExercise.workingWeightUnit = .lb
        progressionExercise.assignmentSource = .exerciseOverride
        harness.context.insert(progressionExercise)

        let session = Session(timestamp: Date(), user_id: user.id, routine: routine, notes: "", program: program)
        session.programBlockId = block.id
        session.programBlockName = block.displayName
        session.programWorkoutId = workout.id
        session.programWorkoutName = workout.displayName
        session.programWeekIndex = 1
        harness.context.insert(session)

        let entry = SessionEntry(order: 0, session: session, exercise: exercise)
        entry.appliedProgressionProfileId = profile.id
        entry.appliedProgressionNameSnapshot = profile.name
        entry.appliedProgressionMiniDescriptionSnapshot = profile.miniDescription
        entry.appliedProgressionTypeRaw = profile.typeRaw
        entry.appliedTargetSetCount = 3
        entry.appliedTargetRepsLow = 8
        entry.appliedTargetRepsHigh = 12
        entry.appliedTargetWeight = 225
        entry.appliedTargetWeightUnitRaw = WeightUnit.lb.rawValue
        entry.appliedProgressionCycleSummary = "225 lb for 3 x 8-12"
        harness.context.insert(entry)

        try harness.context.save()

        let service = ExerciseBackupService(
            context: harness.context,
            currentUserProvider: { user }
        )
        let exportURL = try service.exportExercisesJSON()
        return RichExportFixture(exportURL: exportURL, profileId: profile.id)
    }

    private static func makeHarness() throws -> Harness {
        let schema = Schema([
            User.self,
            Routine.self,
            Exercise.self,
            ExerciseSplitDay.self,
            Program.self,
            ProgramBlock.self,
            ProgramWorkout.self,
            ProgressionProfile.self,
            ProgressionExercise.self,
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
