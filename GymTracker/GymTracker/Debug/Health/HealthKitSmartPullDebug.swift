#if DEBUG
import Foundation
import SwiftData

final class HealthKitSmartPullDebug {
    private static var hasRun = false

    static func runSamples() {
        guard !hasRun else { return }
        hasRun = true

        print("=== HealthKitSmartPullDebug start ===")
        let results = [
            test1RangeDefaults(),
            test2UpsertSetsIsFullySyncedByDayType(),
            test3UnsyncedPastQueryCapsAndSortsNewestFirst()
        ]
        let passCount = results.filter { $0 }.count
        print("=== HealthKitSmartPullDebug done: \(passCount)/\(results.count) passed ===")
    }

    @discardableResult
    private static func test1RangeDefaults() -> Bool {
        let ranges = HealthHistorySyncRange.allCases.map(\.title)
        let pass = check("health-smartpull-test1", ranges == ["3 months", "6 months", "12 months", "24 months", "All"], "Expected ordered shared range options")
            && check("health-smartpull-test1", HealthHistorySyncRange.defaultSelection == .months12, "Expected default range to be 12 months")
        print("[health-smartpull-test1] \(pass ? "PASS" : "FAIL")")
        return pass
    }

    @discardableResult
    private static func test2UpsertSetsIsFullySyncedByDayType() -> Bool {
        do {
            let harness = try makeHarness()
            let repository = LocalHealthKitDailyRepository(modelContext: harness.context)
            let normalizer = HealthKitDateNormalizer()
            let calendar = Calendar.current
            let userId = UUID().uuidString
            let today = normalizer.startOfDay(Date())
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

            try repository.upsertCache(
                with: makeDTO(userId: userId, dayStart: today),
                refreshedAt: Date(),
                isToday: true,
                isFullySynced: false,
                saveImmediately: true
            )
            try repository.upsertCache(
                with: makeDTO(userId: userId, dayStart: yesterday),
                refreshedAt: Date(),
                isToday: false,
                isFullySynced: true,
                saveImmediately: true
            )

            let all = try repository.fetchCachedSummaries(userId: userId)
            let todayRow = all.first(where: { normalizer.sameDay($0.dayStart, today) })
            let yesterdayRow = all.first(where: { normalizer.sameDay($0.dayStart, yesterday) })

            let pass = check("health-smartpull-test2", todayRow?.isFullySynced == false, "Expected today row to remain unsynced")
                && check("health-smartpull-test2", yesterdayRow?.isFullySynced == true, "Expected past day row to be fully synced")
            print("[health-smartpull-test2] \(pass ? "PASS" : "FAIL")")
            return pass
        } catch {
            return fail("health-smartpull-test2", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func test3UnsyncedPastQueryCapsAndSortsNewestFirst() -> Bool {
        do {
            let harness = try makeHarness()
            let repository = LocalHealthKitDailyRepository(modelContext: harness.context)
            let normalizer = HealthKitDateNormalizer()
            let calendar = Calendar.current
            let userId = UUID().uuidString
            let today = normalizer.startOfDay(Date())

            for offset in 1...35 {
                let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
                try repository.upsertCache(
                    with: makeDTO(userId: userId, dayStart: day),
                    refreshedAt: Date(),
                    isToday: false,
                    isFullySynced: false,
                    saveImmediately: true
                )
            }

            let unsynced = try repository.fetchUnsyncedPastSummaries(userId: userId, before: today, limit: 30)
            let sortedNewestFirst = zip(unsynced, unsynced.dropFirst()).allSatisfy { lhs, rhs in
                lhs.dayStart >= rhs.dayStart
            }

            let pass = check("health-smartpull-test3", unsynced.count == 30, "Expected unsynced query to cap at 30 rows")
                && check("health-smartpull-test3", sortedNewestFirst, "Expected unsynced rows sorted newest-first")
                && check("health-smartpull-test3", unsynced.allSatisfy { $0.isFullySynced == false }, "Expected unsynced rows only")
            print("[health-smartpull-test3] \(pass ? "PASS" : "FAIL")")
            return pass
        } catch {
            return fail("health-smartpull-test3", "Unexpected error: \(error)")
        }
    }

    private struct Harness {
        let container: ModelContainer
        let context: ModelContext
    }

    private static func makeHarness() throws -> Harness {
        let schema = Schema([
            SyncMetadataItem.self,
            HealthKitDailyAggregateData.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        return Harness(container: container, context: context)
    }

    private static func makeDTO(userId: String, dayStart: Date) -> HealthKitDailyAggregateData {
        let normalizer = HealthKitDateNormalizer()
        return HealthKitDailyAggregateData(
            userId: userId,
            dayKey: normalizer.dayKey(dayStart),
            dayStart: dayStart,
            steps: 1000,
            activeEnergyKcal: 120,
            restingEnergyKcal: 1400,
            exerciseMinutes: 20,
            standHours: 8,
            moveGoalKcal: 520,
            exerciseGoalMinutes: 30,
            standGoalHours: 12,
            sleepSeconds: 7 * 60 * 60,
            bodyWeightKg: 80,
            schemaVersion: HealthKitDailyAggregateData.currentSchemaVersion
        )
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
