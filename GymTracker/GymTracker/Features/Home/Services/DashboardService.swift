import Foundation
import Combine
import CoreGraphics

@MainActor
final class DashboardService: ServiceBase, ObservableObject {
    @Published var modules: [DashboardModule] = []
    @Published var isEditingMode: Bool = false

    private let userDefaults = UserDefaults.standard
    private let modulesKey = "dashboardModules"

    override func loadFeature() {
        loadModules()
        if modules.isEmpty {
            resetToDefaults()
        }
    }

    var visibleModules: [DashboardModule] {
        modules.filter(\.isVisible)
    }

    func modulesForPreset(_ preset: DashboardPreset) -> [DashboardModule] {
        Self.normalizedModules(Self.modules(for: preset)).filter(\.isVisible)
    }

    func saveVisibleModules(_ updatedVisibleModules: [DashboardModule]) {
        let visibleModules = Self.normalizedVisibleModules(updatedVisibleModules)
        let hiddenModules = Self.normalizedHiddenModules(
            modules.filter { !$0.isVisible }
        )

        var combined = visibleModules
        for hiddenModule in hiddenModules {
            var next = hiddenModule
            next.order = combined.count
            combined.append(next)
        }

        modules = combined
        saveModules()
    }

    func resetToDefaults() {
        modules = Self.normalizedModules(Self.defaultModules())
        saveModules()
    }

    func defaultColumnCount(for availableWidth: CGFloat) -> Int {
        switch availableWidth {
        case ..<720:
            return 2
        case ..<1120:
            return 3
        default:
            return 4
        }
    }

    private func saveModules() {
        do {
            modules = Self.normalizedModules(modules)
            let data = try JSONEncoder().encode(modules)
            userDefaults.set(data, forKey: modulesKey)
        } catch {
            print("Failed to save modules: \(error)")
        }
    }

    private func loadModules() {
        guard let data = userDefaults.data(forKey: modulesKey) else {
            modules = []
            return
        }

        do {
            let decoded = try JSONDecoder().decode([DashboardModule].self, from: data)
            modules = Self.normalizedModules(decoded)
        } catch {
            print("Failed to load modules: \(error)")
            modules = []
        }
    }

    private static func normalizedVisibleModules(_ modules: [DashboardModule]) -> [DashboardModule] {
        normalizedModules(
            modules.map { module in
                var updated = normalizedModule(module)
                updated.isVisible = true
                return updated
            }
        )
    }

    private static func normalizedHiddenModules(_ modules: [DashboardModule]) -> [DashboardModule] {
        normalizedModules(
            modules.map { module in
                var updated = normalizedModule(module)
                updated.isVisible = false
                return updated
            }
        )
    }

    private static func normalizedModules(_ modules: [DashboardModule]) -> [DashboardModule] {
        let sortedModules = modules
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.order != rhs.element.order {
                    return lhs.element.order < rhs.element.order
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)

        return sortedModules.enumerated().map { index, module in
            var normalized = normalizedModule(module)
            normalized.order = index
            return normalized
        }
    }

    private static func normalizedModule(_ module: DashboardModule) -> DashboardModule {
        var normalized = module
        let allowedSizes = normalized.type.allowedSizes
        if !allowedSizes.contains(normalized.size) {
            normalized.size = allowedSizes.first ?? .small
        }
        return normalized
    }

    private static func defaultModules() -> [DashboardModule] {
        [
            DashboardModule(type: .currentWeight, size: .small, order: 0),
            DashboardModule(type: .weeklySteps, size: .small, order: 1),
            DashboardModule(type: .sleep, size: .small, order: 2),
            DashboardModule(type: .timer, size: .small, order: 3),
            DashboardModule(type: .fitnessWorkouts, size: .small, order: 4),
            DashboardModule(type: .activityRings, size: .medium, order: 5),
            DashboardModule(type: .truesight, size: .small, order: 6),
            DashboardModule(type: .nutrition, size: .small, order: 7),
            DashboardModule(type: .sessionVolume, size: .medium, order: 8)
        ]
    }

    private static func modules(for preset: DashboardPreset) -> [DashboardModule] {
        switch preset {
        case .default:
            return defaultModules()
        case .training:
            return [
                DashboardModule(type: .sessionVolume, size: .large, order: 0),
                DashboardModule(type: .timer, size: .small, order: 1),
                DashboardModule(type: .fitnessWorkouts, size: .small, order: 2),
                DashboardModule(type: .truesight, size: .small, order: 3),
                DashboardModule(type: .activityRings, size: .medium, order: 4),
                DashboardModule(type: .weeklySteps, size: .medium, order: 5)
            ]
        case .health:
            return [
                DashboardModule(type: .currentWeight, size: .small, order: 0),
                DashboardModule(type: .sleep, size: .medium, order: 1),
                DashboardModule(type: .activityRings, size: .medium, order: 2),
                DashboardModule(type: .nutrition, size: .large, order: 3),
                DashboardModule(type: .weeklySteps, size: .medium, order: 4)
            ]
        case .minimal:
            return [
                DashboardModule(type: .currentWeight, size: .small, order: 0),
                DashboardModule(type: .timer, size: .small, order: 1),
                DashboardModule(type: .sessionVolume, size: .medium, order: 2),
                DashboardModule(type: .truesight, size: .small, order: 3)
            ]
        }
    }
}
