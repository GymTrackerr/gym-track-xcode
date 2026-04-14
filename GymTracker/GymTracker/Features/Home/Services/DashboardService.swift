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

    func saveModules() {
        do {
            normalizeModules()
            let data = try JSONEncoder().encode(modules)
            userDefaults.set(data, forKey: modulesKey)
        } catch {
            print("Failed to save modules: \(error)")
        }
    }

    func updateModule(_ module: DashboardModule) {
        guard let index = modules.firstIndex(where: { $0.id == module.id }) else { return }
        modules[index] = module
        modules = DashboardPlacementEngine.arrangedModules(from: modules, columns: 2)
        saveModules()
    }

    func updateModuleSize(_ moduleId: String, newSize: ModuleSize) {
        updateModuleSize(moduleId, newSize: newSize, columns: 2)
    }

    func updateModuleSize(_ moduleId: String, newSize: ModuleSize, columns: Int) {
        guard let index = modules.firstIndex(where: { $0.id == moduleId }) else { return }

        let allowedSizes = modules[index].type.allowedSizes
        modules[index].size = allowedSizes.contains(newSize) ? newSize : (allowedSizes.first ?? .small)
        modules = DashboardPlacementEngine.reposition(
            modules,
            moduleId: moduleId,
            desiredPosition: currentPosition(for: moduleId, columns: columns),
            columns: columns
        )
        saveModules()
    }

    func toggleModuleVisibility(_ moduleId: String) {
        guard let index = modules.firstIndex(where: { $0.id == moduleId }) else { return }
        modules[index].isVisible.toggle()
        modules = DashboardPlacementEngine.arrangedModules(from: modules, columns: 2)
        saveModules()
    }

    func setModuleVisibility(_ moduleId: String, isVisible: Bool) {
        setModuleVisibility(moduleId, isVisible: isVisible, columns: 2)
    }

    func setModuleVisibility(_ moduleId: String, isVisible: Bool, columns: Int) {
        guard let index = modules.firstIndex(where: { $0.id == moduleId }) else { return }
        modules[index].isVisible = isVisible
        modules = DashboardPlacementEngine.arrangedModules(from: modules, columns: columns)
        saveModules()
    }

    func getVisibleModules() -> [DashboardModule] {
        getVisibleModules(columns: 2)
    }

    func getVisibleModules(columns: Int) -> [DashboardModule] {
        DashboardPlacementEngine.arrangedModules(from: modules, columns: columns)
            .filter(\.isVisible)
            .sorted(by: DashboardPlacementEngine.layoutSort)
    }

    func addModule(_ type: ModuleType, size: ModuleSize) {
        addModule(type, size: size, columns: 2)
    }

    func addModule(_ type: ModuleType, size: ModuleSize, columns: Int) {
        let nextOrder = (modules.map(\.order).max() ?? -1) + 1
        let normalizedSize = type.allowedSizes.contains(size) ? size : (type.allowedSizes.first ?? .small)

        modules.append(
            DashboardModule(
                type: type,
                size: normalizedSize,
                order: nextOrder,
                isVisible: true
            )
        )

        modules = DashboardPlacementEngine.arrangedModules(from: modules, columns: columns)
        saveModules()
    }

    func removeModule(_ moduleId: String) {
        guard let index = modules.firstIndex(where: { $0.id == moduleId }) else { return }
        modules[index].isVisible = false
        modules = DashboardPlacementEngine.arrangedModules(from: modules, columns: 2)
        saveModules()
    }

    func deleteAllModules() {
        modules = modules.map { module in
            var updated = module
            updated.isVisible = false
            return updated
        }
        modules = DashboardPlacementEngine.arrangedModules(from: modules, columns: 2)
        saveModules()
    }

    func toggleEditMode() {
        isEditingMode.toggle()
    }

    func resetToDefaults() {
        modules = DashboardPlacementEngine.arrangedModules(from: Self.defaultModules(), columns: 2)
        saveModules()
    }

    func modulesSnapshotForEditor() -> [DashboardModule] {
        DashboardPlacementEngine.arrangedModules(from: modules, columns: 2)
    }

    func defaultModulesForEditor() -> [DashboardModule] {
        Self.defaultModules()
    }

    func applyEditorModules(_ updatedModules: [DashboardModule]) {
        modules = DashboardPlacementEngine.arrangedModules(from: updatedModules, columns: 2)
        saveModules()
    }

    func moduleForDisplay(_ moduleId: String, columns: Int) -> DashboardModule? {
        getVisibleModules(columns: columns).first(where: { $0.id == moduleId })
    }

    func applyPreset(_ preset: DashboardPreset, columns: Int) {
        modules = DashboardPlacementEngine.arrangedModules(from: Self.modules(for: preset), columns: columns)
        saveModules()
    }

    func moveModule(_ moduleId: String, direction: DashboardMoveDirection, columns: Int) {
        guard let current = currentPosition(for: moduleId, columns: columns) else { return }

        let target: DashboardGridPoint
        switch direction {
        case .left:
            target = DashboardGridPoint(x: current.x - 1, y: current.y)
        case .right:
            target = DashboardGridPoint(x: current.x + 1, y: current.y)
        case .up:
            target = DashboardGridPoint(x: current.x, y: current.y - 1)
        case .down:
            target = DashboardGridPoint(x: current.x, y: current.y + 1)
        }

        modules = DashboardPlacementEngine.reposition(modules, moduleId: moduleId, desiredPosition: target, columns: columns)
        saveModules()
    }

    func moveModule(_ moduleId: String, toGridX x: Int, gridY y: Int, columns: Int) {
        modules = DashboardPlacementEngine.reposition(
            modules,
            moduleId: moduleId,
            desiredPosition: DashboardGridPoint(x: x, y: y),
            columns: columns
        )
        saveModules()
    }

    func defaultColumnCount(for availableWidth: CGFloat) -> Int {
        DashboardPlacementEngine.defaultColumnCount(for: availableWidth)
    }

    private func loadModules() {
        guard let data = userDefaults.data(forKey: modulesKey) else {
            modules = []
            return
        }

        do {
            modules = try JSONDecoder().decode([DashboardModule].self, from: data)
            normalizeModules()
        } catch {
            print("Failed to load modules: \(error)")
            modules = []
        }
    }

    private func normalizeModules() {
        modules = DashboardPlacementEngine.arrangedModules(from: modules, columns: 2)
    }

    private func currentPosition(for moduleId: String, columns: Int) -> DashboardGridPoint? {
        guard let module = DashboardPlacementEngine.arrangedModules(from: modules, columns: columns)
            .first(where: { $0.id == moduleId }),
              let x = module.gridX,
              let y = module.gridY else {
            return nil
        }

        return DashboardGridPoint(x: x, y: y)
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

struct DashboardGridPoint {
    let x: Int
    let y: Int
}

struct DashboardGridCell: Hashable {
    let x: Int
    let y: Int
}

enum DashboardPlacementEngine {
    static func defaultColumnCount(for availableWidth: CGFloat) -> Int {
        switch availableWidth {
        case ..<720:
            return 2
        case ..<1120:
            return 3
        default:
            return 4
        }
    }

    static func arrangedModules(from modules: [DashboardModule], columns: Int) -> [DashboardModule] {
        let safeColumns = max(columns, 2)

        let visible = modules
            .filter(\.isVisible)
            .sorted(by: preferredLayoutSort)
            .map { module -> DashboardModule in
                var module = module
                if !module.type.allowedSizes.contains(module.size) {
                    module.size = module.type.allowedSizes.first ?? .small
                }
                return module
            }

        let hidden = modules
            .filter { !$0.isVisible }
            .sorted { $0.order < $1.order }

        var occupied = Set<DashboardGridCell>()
        var placedVisible: [DashboardModule] = []

        for module in visible {
            var next = module
            let placement = placementForModule(
                next,
                preferredPosition: preferredPosition(for: next, columns: safeColumns),
                occupied: occupied,
                columns: safeColumns
            )
            next.gridX = placement.x
            next.gridY = placement.y
            occupy(module: next, occupied: &occupied, columns: safeColumns)
            placedVisible.append(next)
        }

        var combined = placedVisible.sorted(by: layoutSort) + hidden
        for index in combined.indices {
            combined[index].order = index
        }
        return combined
    }

    static func reposition(_ modules: [DashboardModule], moduleId: String, desiredPosition: DashboardGridPoint?, columns: Int) -> [DashboardModule] {
        let arranged = arrangedModules(from: modules, columns: columns)
        guard let moved = arranged.first(where: { $0.id == moduleId }) else { return arranged }

        let hidden = arranged.filter { !$0.isVisible }
        let others = arranged
            .filter { $0.isVisible && $0.id != moduleId }
            .sorted(by: layoutSort)

        var occupied = Set<DashboardGridCell>()
        var placedVisible: [DashboardModule] = []

        var movedModule = moved
        let movedPlacement = placementForModule(
            movedModule,
            preferredPosition: desiredPosition ?? preferredPosition(for: movedModule, columns: columns),
            occupied: occupied,
            columns: columns
        )
        movedModule.gridX = movedPlacement.x
        movedModule.gridY = movedPlacement.y
        occupy(module: movedModule, occupied: &occupied, columns: columns)
        placedVisible.append(movedModule)

        for module in others {
            var next = module
            let placement = placementForModule(
                next,
                preferredPosition: preferredPosition(for: next, columns: columns),
                occupied: occupied,
                columns: columns
            )
            next.gridX = placement.x
            next.gridY = placement.y
            occupy(module: next, occupied: &occupied, columns: columns)
            placedVisible.append(next)
        }

        var combined = placedVisible.sorted(by: layoutSort) + hidden
        for index in combined.indices {
            combined[index].order = index
        }
        return combined
    }

    static func layoutSort(lhs: DashboardModule, rhs: DashboardModule) -> Bool {
        let lhsY = lhs.gridY ?? 0
        let rhsY = rhs.gridY ?? 0
        if lhsY != rhsY { return lhsY < rhsY }

        let lhsX = lhs.gridX ?? 0
        let rhsX = rhs.gridX ?? 0
        if lhsX != rhsX { return lhsX < rhsX }

        return lhs.order < rhs.order
    }

    private static func preferredLayoutSort(lhs: DashboardModule, rhs: DashboardModule) -> Bool {
        let lhsY = lhs.gridY ?? Int.max
        let rhsY = rhs.gridY ?? Int.max
        if lhsY != rhsY { return lhsY < rhsY }

        let lhsX = lhs.gridX ?? Int.max
        let rhsX = rhs.gridX ?? Int.max
        if lhsX != rhsX { return lhsX < rhsX }

        return lhs.order < rhs.order
    }

    private static func placementForModule(
        _ module: DashboardModule,
        preferredPosition: DashboardGridPoint?,
        occupied: Set<DashboardGridCell>,
        columns: Int
    ) -> DashboardGridPoint {
        if let preferredPosition {
            let clamped = clamp(preferredPosition, for: module, columns: columns)
            if canPlace(module: module, at: clamped, occupied: occupied, columns: columns) {
                return clamped
            }
        }

        return firstAvailablePosition(for: module, occupied: occupied, columns: columns)
    }

    private static func preferredPosition(for module: DashboardModule, columns: Int) -> DashboardGridPoint? {
        guard let gridX = module.gridX, let gridY = module.gridY else { return nil }
        return clamp(DashboardGridPoint(x: gridX, y: gridY), for: module, columns: columns)
    }

    private static func clamp(_ point: DashboardGridPoint, for module: DashboardModule, columns: Int) -> DashboardGridPoint {
        let maxX = max(columns - min(module.size.columnSpan, columns), 0)
        return DashboardGridPoint(
            x: min(max(point.x, 0), maxX),
            y: max(point.y, 0)
        )
    }

    private static func firstAvailablePosition(
        for module: DashboardModule,
        occupied: Set<DashboardGridCell>,
        columns: Int
    ) -> DashboardGridPoint {
        let maxX = max(columns - min(module.size.columnSpan, columns), 0)

        for y in 0..<128 {
            for x in 0...maxX {
                let candidate = DashboardGridPoint(x: x, y: y)
                if canPlace(module: module, at: candidate, occupied: occupied, columns: columns) {
                    return candidate
                }
            }
        }

        return DashboardGridPoint(x: 0, y: 0)
    }

    private static func canPlace(
        module: DashboardModule,
        at point: DashboardGridPoint,
        occupied: Set<DashboardGridCell>,
        columns: Int
    ) -> Bool {
        let columnSpan = min(module.size.columnSpan, columns)
        guard point.x >= 0, point.y >= 0, point.x + columnSpan <= columns else {
            return false
        }

        for row in point.y..<(point.y + module.size.rowSpan) {
            for column in point.x..<(point.x + columnSpan) {
                if occupied.contains(DashboardGridCell(x: column, y: row)) {
                    return false
                }
            }
        }

        return true
    }

    private static func occupy(module: DashboardModule, occupied: inout Set<DashboardGridCell>, columns: Int) {
        let point = clamp(
            DashboardGridPoint(x: module.gridX ?? 0, y: module.gridY ?? 0),
            for: module,
            columns: columns
        )
        let columnSpan = min(module.size.columnSpan, columns)

        for row in point.y..<(point.y + module.size.rowSpan) {
            for column in point.x..<(point.x + columnSpan) {
                occupied.insert(DashboardGridCell(x: column, y: row))
            }
        }
    }
}
