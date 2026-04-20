#if DEBUG
import Foundation
import SwiftData

final class DashboardFeatureDebug {
    private static var hasRun = false
    private static let modulesKey = "dashboardModules"

    static func runSamples() {
        guard !hasRun else { return }
        hasRun = true

        print("=== DashboardFeatureDebug start ===")
        let results = [
            test1DuplicateModulesPersistAndReloadIndependently()
        ]
        let passCount = results.filter { $0 }.count
        print("=== DashboardFeatureDebug done: \(passCount)/\(results.count) passed ===")
    }

    @discardableResult
    private static func test1DuplicateModulesPersistAndReloadIndependently() -> Bool {
        let defaults = UserDefaults.standard
        let originalData = defaults.data(forKey: modulesKey)
        defer {
            if let originalData {
                defaults.set(originalData, forKey: modulesKey)
            } else {
                defaults.removeObject(forKey: modulesKey)
            }
        }

        do {
            let harness = try makeHarness()
            let service = DashboardService(context: harness.context)

            let firstTimer = DashboardModule(type: .timer, size: .small, order: 0)
            let secondTimer = DashboardModule(type: .timer, size: .medium, order: 1)
            let program = DashboardModule(type: .program, size: .small, order: 2)
            service.saveVisibleModules([firstTimer, secondTimer, program])

            let reloaded = DashboardService(context: harness.context)
            reloaded.loadFeature()

            let visibleModules = reloaded.visibleModules
            let timerModules = visibleModules.filter { $0.type == .timer }
            let programModules = visibleModules.filter { $0.type == .program }

            reloaded.saveVisibleModules(visibleModules.filter { $0.id != firstTimer.id })

            let afterRemoval = DashboardService(context: harness.context)
            afterRemoval.loadFeature()
            let remainingTimers = afterRemoval.visibleModules.filter { $0.type == .timer }

            var ok = true
            ok = ok && check("dashboard-test1", ModuleType.program.allowedSizes == [.small, .medium], "Expected Program module to support only small and medium sizes")
            ok = ok && check("dashboard-test1", timerModules.count == 2, "Expected duplicate timer modules to reload independently")
            ok = ok && check("dashboard-test1", programModules.count == 1, "Expected one program module to reload")
            ok = ok && check("dashboard-test1", remainingTimers.count == 1, "Expected removing one duplicate timer to leave the other intact")
            print("[dashboard-test1] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("dashboard-test1", "Unexpected error: \(error)")
        }
    }

    private struct Harness {
        let container: ModelContainer
        let context: ModelContext
    }

    private static func makeHarness() throws -> Harness {
        let schema = Schema([User.self])
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
