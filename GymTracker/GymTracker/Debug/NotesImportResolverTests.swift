#if DEBUG
import Foundation
import SwiftData

final class NotesImportResolverDebug {
    private static var hasRun = false

    static func runSamples() {
        guard !hasRun else { return }
        hasRun = true

        print("=== NotesImportResolverDebug start ===")

        let results = [
            test1RoutineResolutionIsUserScoped(),
            test2ExerciseResolutionNormalizationAndScoping(),
            test3ResolveDraftResult(),
            test4AliasWritebackHelpers(),
            test5ResolverPrefersLinkedExerciseOverNameCollision()
        ]

        let passCount = results.filter { $0 }.count
        print("=== NotesImportResolverDebug done: \(passCount)/\(results.count) passed ===")
    }

    @discardableResult
    private static func test1RoutineResolutionIsUserScoped() -> Bool {
        do {
            let harness = try makeHarness()
            let resolver = NotesImportResolver()

            let userA = UUID()
            let userB = UUID()

            let routineA = Routine(order: 0, name: "Leg Day", user_id: userA)
            routineA.aliases = ["Lower Body"]
            let routineB = Routine(order: 0, name: "Leg Day", user_id: userB)

            harness.context.insert(routineA)
            harness.context.insert(routineB)
            try harness.context.save()

            let resolvedA = try resolver.resolveRoutine(
                routineNameRaw: "lower-body",
                userId: userA,
                context: harness.context
            )

            let resolvedB = try resolver.resolveRoutine(
                routineNameRaw: "lower-body",
                userId: userB,
                context: harness.context
            )

            var ok = true
            ok = ok && check("resolver-test1", resolvedA?.id == routineA.id, "Expected alias to resolve only for userA routine")
            ok = ok && check("resolver-test1", resolvedB == nil, "Expected no routine for userB alias lookup")
            print("[resolver-test1] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("resolver-test1", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func test2ExerciseResolutionNormalizationAndScoping() -> Bool {
        do {
            let harness = try makeHarness()
            let resolver = NotesImportResolver()

            let userA = UUID()
            let userB = UUID()

            let exerciseA = Exercise(name: "Incline Press", type: .weight, user_id: userA)
            exerciseA.aliases = ["Incline Bench"]

            let exerciseB = Exercise(name: "Incline Press", type: .weight, user_id: userB)
            exerciseB.aliases = ["Incline Bench"]

            harness.context.insert(exerciseA)
            harness.context.insert(exerciseB)
            try harness.context.save()

            let resolutions = try resolver.resolveExercises(
                rawNames: ["incline-bench", "INCLINE PRESS", "unknown move"],
                userId: userA,
                context: harness.context
            )

            var ok = true
            ok = ok && check("resolver-test2", resolutions["incline-bench"]?.resolved?.id == exerciseA.id, "Expected alias to resolve to userA exercise")
            ok = ok && check("resolver-test2", resolutions["INCLINE PRESS"]?.resolved?.id == exerciseA.id, "Expected normalized name to resolve to userA exercise")
            ok = ok && check("resolver-test2", resolutions["unknown move"]?.resolved == nil, "Expected unresolved exercise for unknown move")
            ok = ok && check("resolver-test2", resolutions["incline-bench"]?.candidates.count == 1, "Expected single candidate due to user scoping")
            print("[resolver-test2] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("resolver-test2", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func test3ResolveDraftResult() -> Bool {
        do {
            let harness = try makeHarness()
            let resolver = NotesImportResolver()

            let userId = UUID()

            let routine = Routine(order: 0, name: "Push Day", user_id: userId)
            routine.aliases = ["Push"]

            let bench = Exercise(name: "Bench Press", type: .weight, user_id: userId)
            bench.aliases = ["Bench"]
            let run = Exercise(name: "Run", type: .run, user_id: userId)

            harness.context.insert(routine)
            harness.context.insert(bench)
            harness.context.insert(run)
            try harness.context.save()

            let draft = NotesImportDraft(
                originalText: "sample",
                parsedDate: Date(),
                startTime: nil,
                endTime: nil,
                routineNameRaw: "push",
                items: [
                    .strength(
                        ParsedStrength(
                            exerciseNameRaw: "bench",
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
                                    durationSeconds: 1200,
                                    distance: 2,
                                    distanceUnit: .mi,
                                    paceSeconds: nil
                                )
                            ],
                            notes: nil
                        )
                    ),
                    .strength(
                        ParsedStrength(
                            exerciseNameRaw: "Mystery Lift",
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

            let result = try resolver.resolve(draft: draft, userId: userId, context: harness.context)

            var ok = true
            ok = ok && check("resolver-test3", result.resolvedRoutine?.id == routine.id, "Expected routine alias to resolve")
            ok = ok && check("resolver-test3", result.resolvedExercises["bench"]?.id == bench.id, "Expected bench alias to resolve")
            ok = ok && check("resolver-test3", result.resolvedExercises["Run"]?.id == run.id, "Expected run to resolve")
            ok = ok && check("resolver-test3", result.unresolvedExercises == ["Mystery Lift"], "Expected unresolved list to include only Mystery Lift")
            print("[resolver-test3] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("resolver-test3", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func test4AliasWritebackHelpers() -> Bool {
        let resolver = NotesImportResolver()
        let userId = UUID()

        let routine = Routine(order: 0, name: "Upper", user_id: userId)
        let exercise = Exercise(name: "Deadlift", type: .weight, user_id: userId)

        var ok = true

        let routineAdded = resolver.addRoutineAliasIfNeeded(
            routine: routine,
            aliasRaw: " upper day ",
            rememberAlias: true
        )

        let routineDuplicate = resolver.addRoutineAliasIfNeeded(
            routine: routine,
            aliasRaw: "UPPER DAY",
            rememberAlias: true
        )

        let exerciseSkipped = resolver.addExerciseAliasIfNeeded(
            exercise: exercise,
            aliasRaw: "deadlift",
            rememberAlias: true
        )

        let exerciseAdded = resolver.addExerciseAliasIfNeeded(
            exercise: exercise,
            aliasRaw: "DL",
            rememberAlias: true
        )

        let exerciseRememberOff = resolver.addExerciseAliasIfNeeded(
            exercise: exercise,
            aliasRaw: "dead",
            rememberAlias: false
        )

        ok = ok && check("resolver-test4", routineAdded, "Expected routine alias to be added")
        ok = ok && check("resolver-test4", !routineDuplicate, "Expected normalized duplicate routine alias to be rejected")
        ok = ok && check("resolver-test4", !exerciseSkipped, "Expected alias matching exercise name to be rejected")
        ok = ok && check("resolver-test4", exerciseAdded, "Expected exercise alias DL to be added")
        ok = ok && check("resolver-test4", !exerciseRememberOff, "Expected no alias add when rememberAlias=false")

        print("[resolver-test4] \(ok ? "PASS" : "FAIL")")
        return ok
    }

    @discardableResult
    private static func test5ResolverPrefersLinkedExerciseOverNameCollision() -> Bool {
        do {
            let harness = try makeHarness()
            let resolver = NotesImportResolver()
            let userId = UUID()

            let canonical = Exercise(name: "Alternating Hammer Curl", type: .weight, user_id: userId)
            canonical.aliases = ["Alternate Hammer Curl"]
            let duplicate = Exercise(name: "Alternate Hammer Curl", type: .weight, user_id: userId)

            harness.context.insert(canonical)
            harness.context.insert(duplicate)

            let session = Session(timestamp: Date(), user_id: userId, routine: nil, notes: "")
            harness.context.insert(session)
            let entry = SessionEntry(order: 0, session: session, exercise: canonical)
            harness.context.insert(entry)
            session.sessionEntries.append(entry)
            canonical.sessionEntries.append(entry)

            try harness.context.save()

            let resolutions = try resolver.resolveExercises(
                rawNames: ["Alternate Hammer Curl"],
                userId: userId,
                context: harness.context
            )

            var ok = true
            ok = ok && check(
                "resolver-test5",
                resolutions["Alternate Hammer Curl"]?.resolved?.id == canonical.id,
                "Expected resolver to prefer linked canonical exercise over name-collision duplicate"
            )
            print("[resolver-test5] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("resolver-test5", "Unexpected error: \(error)")
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
