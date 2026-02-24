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
            test4CommitFailsWhenExerciseUnresolved()
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

            let draft = NotesImportDraft(
                originalText: "sample",
                parsedDate: date,
                startTime: start,
                endTime: nil,
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
            ok = ok && check("writer-test2", session.notes.contains("Missing end time; estimated end time used."), "Expected missing-end warning in notes")

            if let strengthEntry = session.sessionEntries.first(where: { $0.exercise.id == bench.id }) {
                ok = ok && check("writer-test2", strengthEntry.sets.count == 2, "Expected two strength sets")

                if strengthEntry.sets.count >= 2 {
                    let firstRep = strengthEntry.sets[0].sessionReps.first
                    let secondRep = strengthEntry.sets[1].sessionReps.first

                    ok = ok && check("writer-test2", firstRep?.weight == 185, "Expected explicit strength weight")
                    ok = ok && check("writer-test2", firstRep?.count == 8, "Expected explicit rep count")
                    ok = ok && check("writer-test2", strengthEntry.sets[0].restSeconds == 90, "Expected restSeconds to persist")

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
                if let cardioSet = cardioEntry.sets.first {
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

            let draft = NotesImportDraft(
                originalText: "sample",
                parsedDate: date,
                startTime: nil,
                endTime: nil,
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
