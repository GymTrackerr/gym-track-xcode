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
            test1MergeRelinksReferencesAndDeletesDuplicate(),
            test2CatalogApplyDoesNotMutateUserCreatedExercise(),
            test3ArrayOrEnvelopeDecodesBareArrayAndListEnvelope(),
            test4RouteResolverKeepsCatalogOnPublicRoute(),
            test5ArrayOrEnvelopeRejectsMalformedEnvelope()
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

    @discardableResult
    private static func test2CatalogApplyDoesNotMutateUserCreatedExercise() -> Bool {
        do {
            let harness = try makeHarness()
            let currentUser = User(name: "Current")
            harness.context.insert(currentUser)

            let userCreated = Exercise(name: "My Press", type: .weight, user_id: currentUser.id, isUserCreated: true)
            userCreated.npId = "bench_press"
            harness.context.insert(userCreated)
            try harness.context.save()

            let repository = LocalExerciseRepository(modelContext: harness.context)
            let dto = ExerciseDTO(
                id: "bench_press",
                name: "Bench Press",
                force: nil,
                level: nil,
                mechanic: nil,
                equipment: "barbell",
                primaryMuscles: ["chest"],
                secondaryMuscles: ["triceps"],
                instructions: ["Press bar up"],
                category: "strength",
                images: ["/v1/exercisedb/static/bench_press/image1.jpg", "/v1/exercisedb/static/bench_press/animation.gif"]
            )

            _ = try repository.applyCatalogExercises([dto], for: currentUser.id, allowInsert: false)
            let all = try harness.context.fetch(FetchDescriptor<Exercise>())

            let pass = check("merge-test2", all.count == 1, "Expected no catalog insert in update-only mode")
                && check("merge-test2", all.first?.name == "My Press", "Expected user-created exercise to remain unchanged")
                && check("merge-test2", all.first?.isUserCreated == true, "Expected exercise to remain user-created")
            print("[merge-test2] \(pass ? "PASS" : "FAIL")")
            return pass
        } catch {
            return fail("merge-test2", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func test3ArrayOrEnvelopeDecodesBareArrayAndListEnvelope() -> Bool {
        do {
            let bareArrayJSON = """
            [{"id":"x","name":"X","force":null,"level":null,"mechanic":null,"equipment":null,"primaryMuscles":[],"secondaryMuscles":[],"instructions":[],"category":"strength","images":[]}]
            """.data(using: .utf8) ?? Data()
            let envelopeJSON = """
            {"list":[{"id":"y","name":"Y","force":null,"level":null,"mechanic":null,"equipment":null,"primaryMuscles":[],"secondaryMuscles":[],"instructions":[],"category":"strength","images":[]}]}
            """.data(using: .utf8) ?? Data()

            let bareDecoded = try ArrayOrEnvelopeDecoder.decode([ExerciseDTO].self, from: bareArrayJSON)
            let envelopeDecoded = try ArrayOrEnvelopeDecoder.decode([ExerciseDTO].self, from: envelopeJSON)

            let pass = check("merge-test3", bareDecoded.count == 1, "Expected one DTO from bare array")
                && check("merge-test3", envelopeDecoded.count == 1, "Expected one DTO from envelope list")
                && check("merge-test3", bareDecoded.first?.id == "x", "Expected bare array id x")
                && check("merge-test3", envelopeDecoded.first?.id == "y", "Expected envelope id y")
            print("[merge-test3] \(pass ? "PASS" : "FAIL")")
            return pass
        } catch {
            return fail("merge-test3", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func test4RouteResolverKeepsCatalogOnPublicRoute() -> Bool {
        final class StubCatalogSource: ExerciseCatalogSource {
            let routeDescription: String
            init(routeDescription: String) { self.routeDescription = routeDescription }
            func fetchCatalog(ifNoneMatch: String?) async throws -> ExerciseCatalogFetchResult {
                _ = ifNoneMatch
                return .notModified(etag: nil)
            }
        }

        final class StubUserSource: UserExerciseSource {
            let routeDescription: String
            init(routeDescription: String) { self.routeDescription = routeDescription }
            func fetchUserExercises() async throws -> [GymTrackerExerciseDTO] { [] }
        }

        let catalog = StubCatalogSource(routeDescription: "/v1/exercisedb")
        let user = StubUserSource(routeDescription: "/v1/exercises?source=user")
        let resolver = ExerciseRouteResolver(catalogSource: catalog, userSource: user)

        let loggedOutCatalogRoute = resolver.catalogSource(for: false).routeDescription
        let loggedInCatalogRoute = resolver.catalogSource(for: true).routeDescription
        let loggedOutUserRoute = resolver.userSource(for: false)
        let loggedInUserRoute = resolver.userSource(for: true)?.routeDescription

        let pass = check("merge-test4", loggedOutCatalogRoute == "/v1/exercisedb", "Expected logged-out catalog route to use public ExerciseDB")
            && check("merge-test4", loggedInCatalogRoute == "/v1/exercisedb", "Expected logged-in catalog route to remain public ExerciseDB")
            && check("merge-test4", loggedOutUserRoute == nil, "Expected logged-out user route to be nil")
            && check("merge-test4", loggedInUserRoute == "/v1/exercises?source=user", "Expected logged-in user route to use /v1/exercises?source=user")
        print("[merge-test4] \(pass ? "PASS" : "FAIL")")
        return pass
    }

    @discardableResult
    private static func test5ArrayOrEnvelopeRejectsMalformedEnvelope() -> Bool {
        let malformedJSON = "{}".data(using: .utf8) ?? Data()
        do {
            _ = try ArrayOrEnvelopeDecoder.decode([ExerciseDTO].self, from: malformedJSON)
            return fail("merge-test5", "Expected malformed envelope decode to throw")
        } catch {
            print("[merge-test5] PASS")
            return true
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
