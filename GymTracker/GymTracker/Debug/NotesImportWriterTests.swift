#if DEBUG
import Foundation
import SwiftData

final class NotesImportWriterDebug {
    private static var hasRun = false

    static func runSamples() {
        guard !hasRun else { return }
        hasRun = true

        print("=== NotesImportWriterDebug start ===")

        let results = [
            test1DuplicateCheckIsUserScoped(),
            test2CommitPersistsStrengthAndCardio(),
            test3CommitFailsWhenDateMissing(),
            test4CommitFailsWhenExerciseUnresolved(),
            test5CreateRoutinePopulatesTemplate(),
            test6ExistingRoutineDoesNotPopulateTemplate(),
            test7NoneRoutineDoesNotAttachOrPopulate(),
            test8DropSetSegmentsPersistInOrder()
        ]

        let passCount = results.filter { $0 }.count
        print("=== NotesImportWriterDebug done: \(passCount)/\(results.count) passed ===")
    }

    @discardableResult
    private static func test1DuplicateCheckIsUserScoped() -> Bool {
        do {
            let harness = try makeHarness()
            let writer = NotesImportWriterService()

            let userA = UUID()
            let userB = UUID()

            let existing = Session(timestamp: Date(), user_id: userA, routine: nil, notes: "")
            existing.importHash = "hash-a"
            harness.context.insert(existing)
            try harness.context.save()

            let draft = NotesImportDraft(
                originalText: "sample",
                parsedDate: Date(),
                startTime: nil,
                endTime: nil,
                routineNameRaw: nil,
                items: [],
                unknownLines: [],
                warnings: [],
                importHash: "hash-a"
            )

            let foundForA = try writer.duplicateExists(draft: draft, userId: userA, context: harness.context)
            let foundForB = try writer.duplicateExists(draft: draft, userId: userB, context: harness.context)

            var ok = true
            ok = ok && check("writer-test1", foundForA, "Expected duplicate for same user and hash")
            ok = ok && check("writer-test1", !foundForB, "Expected no duplicate across different user")
            print("[writer-test1] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("writer-test1", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func test2CommitPersistsStrengthAndCardio() -> Bool {
        do {
            let harness = try makeHarness()
            let writer = NotesImportWriterService()

            let userId = UUID()
            let routine = Routine(order: 0, name: "Push", user_id: userId)
            let bench = Exercise(name: "Bench Press", type: .weight, user_id: userId)
            let run = Exercise(name: "Run", type: .run, user_id: userId)

            harness.context.insert(routine)
            harness.context.insert(bench)
            harness.context.insert(run)
            try harness.context.save()

            let date = Date()
            let start = Calendar.current.date(bySettingHour: 9, minute: 30, second: 0, of: date) ?? date
            let end = Calendar.current.date(byAdding: .minute, value: 75, to: start) ?? start

            let draft = NotesImportDraft(
                originalText: "sample",
                parsedDate: date,
                startTime: start,
                endTime: end,
                routineNameRaw: "Push",
                items: [
                    .strength(
                        ParsedStrength(
                            exerciseNameRaw: "Bench Press",
                            sets: [
                                ParsedStrengthSet(
                                    reps: 8,
                                    weight: 185,
                                    weightUnit: .lb,
                                    perSideWeight: nil,
                                    baseWeight: nil,
                                    isPerSide: false,
                                    restSeconds: 90
                                ),
                                ParsedStrengthSet(
                                    reps: 10,
                                    weight: nil,
                                    weightUnit: .kg,
                                    perSideWeight: 35,
                                    baseWeight: 20,
                                    isPerSide: true,
                                    restSeconds: nil
                                )
                            ],
                            notes: "Strength notes"
                        )
                    ),
                    .cardio(
                        ParsedCardio(
                            exerciseNameRaw: "Run",
                            sets: [
                                ParsedCardioSet(
                                    durationSeconds: 1200,
                                    distance: 2,
                                    distanceUnit: .mi,
                                    paceSeconds: 360
                                )
                            ],
                            notes: "Cardio notes"
                        )
                    )
                ],
                unknownLines: ["Started watch workout"],
                warnings: ["Header had minor issue"],
                importHash: "hash-commit"
            )

            let resolution = ResolutionResult(
                resolvedRoutine: routine,
                resolvedExercises: [
                    "Bench Press": bench,
                    "Run": run
                ],
                unresolvedExercises: []
            )

            let session = try writer.commit(
                draft: draft,
                resolution: resolution,
                userId: userId,
                context: harness.context,
                defaultWeightUnit: .lb
            )

            var ok = true
            ok = ok && check("writer-test2", session.user_id == userId, "Expected session.user_id to match input")
            ok = ok && check("writer-test2", session.importHash == "hash-commit", "Expected importHash to persist")
            ok = ok && check("writer-test2", session.routine?.id == routine.id, "Expected routine assignment")
            ok = ok && check("writer-test2", session.sessionEntries.count == 2, "Expected two entries (strength + cardio)")
            ok = ok && check("writer-test2", session.notes.contains("Import warnings:"), "Expected warnings section in notes")
            ok = ok && check("writer-test2", session.notes.contains("Unparsed lines:"), "Expected unknown-lines section in notes")

            if let strengthEntry = session.sessionEntries.first(where: { $0.exercise.id == bench.id }) {
                ok = ok && check("writer-test2", strengthEntry.sets.count == 2, "Expected two strength sets")
                ok = ok && check("writer-test2", strengthEntry.isCompleted, "Expected imported strength entry to auto-complete")

                if strengthEntry.sets.count >= 2 {
                    let orderedSets = strengthEntry.sets.sorted { lhs, rhs in
                        if lhs.order != rhs.order { return lhs.order < rhs.order }
                        return lhs.id.uuidString < rhs.id.uuidString
                    }
                    let firstRep = orderedSets[0].sessionReps.first
                    let secondRep = orderedSets[1].sessionReps.first

                    ok = ok && check("writer-test2", orderedSets[0].isCompleted, "Expected imported strength set 1 to auto-complete")
                    ok = ok && check("writer-test2", orderedSets[1].isCompleted, "Expected imported strength set 2 to auto-complete")
                    ok = ok && check("writer-test2", firstRep?.weight == 185, "Expected explicit strength weight")
                    ok = ok && check("writer-test2", firstRep?.count == 8, "Expected explicit rep count")
                    ok = ok && check("writer-test2", orderedSets[0].restSeconds == 90, "Expected restSeconds to persist")

                    ok = ok && check("writer-test2", secondRep?.weight == 0, "Expected weightless set to persist as 0")
                    ok = ok && check("writer-test2", secondRep?.weight_unit == WeightUnit.lb.rawValue, "Expected default weight unit to be used for weightless set")
                    ok = ok && check("writer-test2", secondRep?.notes == "Imported: weight not specified (treated as 0).", "Expected weightless rep note")
                    ok = ok && check("writer-test2", secondRep?.baseWeight == 20, "Expected baseWeight metadata")
                    ok = ok && check("writer-test2", secondRep?.perSideWeight == 35, "Expected perSideWeight metadata")
                    ok = ok && check("writer-test2", secondRep?.isPerSide == true, "Expected isPerSide metadata")
                }
            } else {
                ok = false
                print("[writer-test2] FAIL: Missing strength entry")
            }

            if let cardioEntry = session.sessionEntries.first(where: { $0.exercise.id == run.id }) {
                ok = ok && check("writer-test2", cardioEntry.sets.count == 1, "Expected one cardio set")
                ok = ok && check("writer-test2", cardioEntry.isCompleted, "Expected imported cardio entry to auto-complete")
                if let cardioSet = cardioEntry.sets.first {
                    ok = ok && check("writer-test2", cardioSet.isCompleted, "Expected imported cardio set to auto-complete")
                    ok = ok && check("writer-test2", cardioSet.durationSeconds == 1200, "Expected cardio duration")
                    ok = ok && check("writer-test2", cardioSet.distance == 2, "Expected cardio distance")
                    ok = ok && check("writer-test2", cardioSet.distanceUnit == .mi, "Expected cardio distance unit")
                    ok = ok && check("writer-test2", cardioSet.paceSeconds == 360, "Expected cardio pace")
                    ok = ok && check("writer-test2", cardioSet.sessionReps.isEmpty, "Expected no reps for cardio set")
                }
            } else {
                ok = false
                print("[writer-test2] FAIL: Missing cardio entry")
            }

            print("[writer-test2] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("writer-test2", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func test3CommitFailsWhenDateMissing() -> Bool {
        do {
            let harness = try makeHarness()
            let writer = NotesImportWriterService()

            let userId = UUID()
            let draft = NotesImportDraft(
                originalText: "sample",
                parsedDate: nil,
                startTime: nil,
                endTime: nil,
                routineNameRaw: nil,
                items: [],
                unknownLines: [],
                warnings: [],
                importHash: "hash"
            )

            let resolution = ResolutionResult(
                resolvedRoutine: nil,
                resolvedExercises: [:],
                unresolvedExercises: []
            )

            do {
                _ = try writer.commit(
                    draft: draft,
                    resolution: resolution,
                    userId: userId,
                    context: harness.context,
                    defaultWeightUnit: .lb
                )
                return fail("writer-test3", "Expected missingDate error")
            } catch let error as NotesImportWriterError {
                switch error {
                case .missingDate:
                    print("[writer-test3] PASS")
                    return true
                default:
                    return fail("writer-test3", "Expected missingDate, got \(error)")
                }
            }
        } catch {
            return fail("writer-test3", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func test4CommitFailsWhenExerciseUnresolved() -> Bool {
        do {
            let harness = try makeHarness()
            let writer = NotesImportWriterService()

            let userId = UUID()
            let date = Date()
            let start = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: date) ?? date
            let end = Calendar.current.date(byAdding: .minute, value: 45, to: start) ?? start

            let draft = NotesImportDraft(
                originalText: "sample",
                parsedDate: date,
                startTime: start,
                endTime: end,
                routineNameRaw: nil,
                items: [
                    .strength(
                        ParsedStrength(
                            exerciseNameRaw: "Unresolved Move",
                            sets: [
                                ParsedStrengthSet(
                                    reps: 5,
                                    weight: 100,
                                    weightUnit: .lb,
                                    perSideWeight: nil,
                                    baseWeight: nil,
                                    isPerSide: false,
                                    restSeconds: nil
                                )
                            ],
                            notes: nil
                        )
                    )
                ],
                unknownLines: [],
                warnings: [],
                importHash: "hash"
            )

            let resolution = ResolutionResult(
                resolvedRoutine: nil,
                resolvedExercises: [:],
                unresolvedExercises: ["Unresolved Move"]
            )

            do {
                _ = try writer.commit(
                    draft: draft,
                    resolution: resolution,
                    userId: userId,
                    context: harness.context,
                    defaultWeightUnit: .lb
                )
                return fail("writer-test4", "Expected unresolvedExercises error")
            } catch let error as NotesImportWriterError {
                switch error {
                case .unresolvedExercises(let names):
                    let ok = check("writer-test4", names.contains("Unresolved Move"), "Expected unresolved name in error payload")
                    print("[writer-test4] \(ok ? "PASS" : "FAIL")")
                    return ok
                default:
                    return fail("writer-test4", "Expected unresolvedExercises, got \(error)")
                }
            }
        } catch {
            return fail("writer-test4", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func test5CreateRoutinePopulatesTemplate() -> Bool {
        do {
            let harness = try makeHarness()
            let writer = NotesImportWriterService()

            let userId = UUID()
            let createdRoutine = Routine(order: 0, name: "Imported Routine", user_id: userId)
            let squat = Exercise(name: "Back Squat", type: .weight, user_id: userId)
            let bike = Exercise(name: "Indoor cycle", type: .bike, user_id: userId)

            harness.context.insert(createdRoutine)
            harness.context.insert(squat)
            harness.context.insert(bike)
            try harness.context.save()

            let draft = NotesImportDraft(
                originalText: "sample",
                parsedDate: Date(),
                startTime: Date(),
                endTime: Date().addingTimeInterval(3600),
                routineNameRaw: "Leg Day",
                items: [
                    .strength(
                        ParsedStrength(
                            exerciseNameRaw: "Back Squat",
                            sets: [
                                ParsedStrengthSet(
                                    reps: 5,
                                    weight: 225,
                                    weightUnit: .lb,
                                    perSideWeight: nil,
                                    baseWeight: nil,
                                    isPerSide: false,
                                    restSeconds: nil
                                )
                            ],
                            notes: nil
                        )
                    ),
                    .cardio(
                        ParsedCardio(
                            exerciseNameRaw: "Indoor cycle",
                            sets: [
                                ParsedCardioSet(
                                    durationSeconds: 600,
                                    distance: 3,
                                    distanceUnit: .km,
                                    paceSeconds: nil
                                )
                            ],
                            notes: nil
                        )
                    )
                ],
                unknownLines: [],
                warnings: [],
                importHash: "hash-create-routine"
            )

            let resolution = ResolutionResult(
                resolvedRoutine: createdRoutine,
                resolvedExercises: [
                    "Back Squat": squat,
                    "Indoor cycle": bike
                ],
                unresolvedExercises: [],
                createdRoutineId: createdRoutine.id
            )

            _ = try writer.commit(
                draft: draft,
                resolution: resolution,
                userId: userId,
                context: harness.context,
                defaultWeightUnit: .lb
            )

            var ok = true
            let orderedSplits = createdRoutine.exerciseSplits.sorted { lhs, rhs in
                if lhs.order != rhs.order { return lhs.order < rhs.order }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            ok = ok && check("writer-test5", createdRoutine.exerciseSplits.count == 2, "Expected new routine template to receive imported exercises")
            ok = ok && check("writer-test5", orderedSplits[0].exercise.id == squat.id, "Expected first split to match draft order")
            ok = ok && check("writer-test5", orderedSplits[1].exercise.id == bike.id, "Expected second split to match draft order")
            print("[writer-test5] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("writer-test5", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func test6ExistingRoutineDoesNotPopulateTemplate() -> Bool {
        do {
            let harness = try makeHarness()
            let writer = NotesImportWriterService()

            let userId = UUID()
            let existingRoutine = Routine(order: 0, name: "Push", user_id: userId)
            let bench = Exercise(name: "Bench Press", type: .weight, user_id: userId)
            let run = Exercise(name: "Run", type: .run, user_id: userId)

            harness.context.insert(existingRoutine)
            harness.context.insert(bench)
            harness.context.insert(run)
            let existingSplit = ExerciseSplitDay(order: 0, routine: existingRoutine, exercise: bench)
            harness.context.insert(existingSplit)
            existingRoutine.exerciseSplits.append(existingSplit)
            try harness.context.save()

            let draft = NotesImportDraft(
                originalText: "sample",
                parsedDate: Date(),
                startTime: Date(),
                endTime: Date().addingTimeInterval(3600),
                routineNameRaw: "Push",
                items: [
                    .strength(
                        ParsedStrength(
                            exerciseNameRaw: "Bench Press",
                            sets: [
                                ParsedStrengthSet(
                                    reps: 8,
                                    weight: 185,
                                    weightUnit: .lb,
                                    perSideWeight: nil,
                                    baseWeight: nil,
                                    isPerSide: false,
                                    restSeconds: nil
                                )
                            ],
                            notes: nil
                        )
                    ),
                    .cardio(
                        ParsedCardio(
                            exerciseNameRaw: "Run",
                            sets: [
                                ParsedCardioSet(
                                    durationSeconds: 300,
                                    distance: 1,
                                    distanceUnit: .mi,
                                    paceSeconds: nil
                                )
                            ],
                            notes: nil
                        )
                    )
                ],
                unknownLines: [],
                warnings: [],
                importHash: "hash-existing-routine"
            )

            let resolution = ResolutionResult(
                resolvedRoutine: existingRoutine,
                resolvedExercises: [
                    "Bench Press": bench,
                    "Run": run
                ],
                unresolvedExercises: []
            )

            _ = try writer.commit(
                draft: draft,
                resolution: resolution,
                userId: userId,
                context: harness.context,
                defaultWeightUnit: .lb
            )

            var ok = true
            ok = ok && check("writer-test6", existingRoutine.exerciseSplits.count == 1, "Expected matched/existing routine template to remain unchanged")
            ok = ok && check("writer-test6", existingRoutine.exerciseSplits[0].exercise.id == bench.id, "Expected existing split to remain untouched")
            print("[writer-test6] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("writer-test6", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func test7NoneRoutineDoesNotAttachOrPopulate() -> Bool {
        do {
            let harness = try makeHarness()
            let writer = NotesImportWriterService()

            let userId = UUID()
            let untouchedRoutine = Routine(order: 0, name: "Existing", user_id: userId)
            let bike = Exercise(name: "Bike", type: .bike, user_id: userId)

            harness.context.insert(untouchedRoutine)
            harness.context.insert(bike)
            try harness.context.save()

            let draft = NotesImportDraft(
                originalText: "sample",
                parsedDate: Date(),
                startTime: Date(),
                endTime: Date().addingTimeInterval(3600),
                routineNameRaw: nil,
                items: [
                    .cardio(
                        ParsedCardio(
                            exerciseNameRaw: "Bike",
                            sets: [
                                ParsedCardioSet(
                                    durationSeconds: 240,
                                    distance: 2,
                                    distanceUnit: .km,
                                    paceSeconds: nil
                                )
                            ],
                            notes: nil
                        )
                    )
                ],
                unknownLines: [],
                warnings: [],
                importHash: "hash-none-routine"
            )

            let resolution = ResolutionResult(
                resolvedRoutine: nil,
                resolvedExercises: [
                    "Bike": bike
                ],
                unresolvedExercises: []
            )

            let session = try writer.commit(
                draft: draft,
                resolution: resolution,
                userId: userId,
                context: harness.context,
                defaultWeightUnit: .lb
            )

            var ok = true
            ok = ok && check("writer-test7", session.routine == nil, "Expected session routine to remain nil in none mode")
            ok = ok && check("writer-test7", untouchedRoutine.exerciseSplits.isEmpty, "Expected unrelated routine template to remain unchanged")
            print("[writer-test7] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("writer-test7", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func test8DropSetSegmentsPersistInOrder() -> Bool {
        do {
            let harness = try makeHarness()
            let writer = NotesImportWriterService()

            let userId = UUID()
            let bench = Exercise(name: "Bench Press", type: .weight, user_id: userId)
            harness.context.insert(bench)
            try harness.context.save()

            let draft = NotesImportDraft(
                originalText: "sample",
                parsedDate: Date(),
                startTime: Date(),
                endTime: Date().addingTimeInterval(1800),
                routineNameRaw: nil,
                items: [
                    .strength(
                        ParsedStrength(
                            exerciseNameRaw: "Bench Press",
                            sets: [
                                ParsedStrengthSet(
                                    reps: 6,
                                    weight: 25,
                                    weightUnit: .kg,
                                    perSideWeight: nil,
                                    baseWeight: nil,
                                    isPerSide: false,
                                    restSeconds: nil,
                                    repSegments: [
                                        ParsedRepSegment(reps: 6, weight: 25, weightUnit: .kg, sourceRawReps: nil),
                                        ParsedRepSegment(reps: 3, weight: 22.5, weightUnit: .kg, sourceRawReps: nil)
                                    ]
                                )
                            ],
                            notes: nil
                        )
                    )
                ],
                unknownLines: [],
                warnings: [],
                importHash: "hash-drop-segments"
            )

            let resolution = ResolutionResult(
                resolvedRoutine: nil,
                resolvedExercises: ["Bench Press": bench],
                unresolvedExercises: []
            )

            let session = try writer.commit(
                draft: draft,
                resolution: resolution,
                userId: userId,
                context: harness.context,
                defaultWeightUnit: .lb
            )

            var ok = true
            guard let strengthEntry = session.sessionEntries.first else {
                return fail("writer-test8", "Expected imported entry")
            }
            ok = ok && check("writer-test8", strengthEntry.sets.count == 1, "Expected one top-level SessionSet")
            if let set = strengthEntry.sets.first {
                ok = ok && check("writer-test8", set.isDropSet, "Expected drop set flag for multi-segment set")
                ok = ok && check("writer-test8", set.sessionReps.count == 2, "Expected two reps under one set")
                if set.sessionReps.count == 2 {
                    let first = set.sessionReps[0]
                    let second = set.sessionReps[1]
                    ok = ok && check("writer-test8", first.count == 6 && first.weight == 25, "Expected first segment persisted first")
                    ok = ok && check("writer-test8", second.count == 3 && second.weight == 22.5, "Expected drop segment persisted second")
                }
            }

            print("[writer-test8] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("writer-test8", "Unexpected error: \(error)")
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
