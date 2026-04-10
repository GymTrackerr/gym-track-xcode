import Foundation
import SwiftUI
import Combine
//import CoreData

class DashboardService: ServiceBase, ObservableObject {
    @Published var modules: [DashboardModule] = []
    @Published var isEditingMode: Bool = false
    
    private let userDefaults = UserDefaults.standard
    private let modulesKey = "dashboardModules"

    private static func makeDefaultModules() -> [DashboardModule] {
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
    
    override func loadFeature() {
        loadModules()
        if modules.isEmpty {
            loadDefaultModules()
        }
    }
    
    // MARK: - Default Configuration
    private func loadDefaultModules() {
        self.modules = Self.makeDefaultModules()
        normalizeModules()
        saveModules()
    }
    
    // MARK: - Persistence
    func saveModules() {
        do {
            normalizeModules()
            let data = try JSONEncoder().encode(modules)
            userDefaults.set(data, forKey: modulesKey)
        } catch {
            print("Failed to save modules: \(error)")
        }
    }
    
    private func loadModules() {
        guard let data = userDefaults.data(forKey: modulesKey) else { 
            print("No saved modules found, will create defaults")
            return 
        }
        do {
            modules = try JSONDecoder().decode([DashboardModule].self, from: data)
            normalizeModules()
            print("Loaded \(modules.count) modules from UserDefaults")
        } catch {
            print("Failed to load modules: \(error), will create defaults")
        }
        
    }
    
    // MARK: - Module Management
    func updateModule(_ module: DashboardModule) {
        if let index = modules.firstIndex(where: { $0.id == module.id }) {
            modules[index] = module
            normalizeModules()
            modules = modules  // Trigger @Published update
            saveModules()
        }
    }
    
    func toggleModuleVisibility(_ moduleId: String) {
        if let index = modules.firstIndex(where: { $0.id == moduleId }) {
            modules[index].isVisible.toggle()
            modules = modules  // Trigger @Published update
            saveModules()
        }
    }
    
    func updateModuleSize(_ moduleId: String, newSize: ModuleSize) {
        if let index = modules.firstIndex(where: { $0.id == moduleId }) {
            let allowedSizes = modules[index].type.allowedSizes
            modules[index].size = allowedSizes.contains(newSize) ? newSize : (allowedSizes.first ?? .small)
            modules = modules  // Trigger @Published update
            saveModules()
        }
    }
    
    func reorderModules(_ indices: IndexSet, with source: Int) {
        modules.move(fromOffsets: indices, toOffset: source)
        normalizeModules()
        modules = modules  // Trigger @Published update
        saveModules()
    }

    func reorderVisibleModules(_ indices: IndexSet, to destination: Int) {
        var visible = getVisibleModules()
        visible.move(fromOffsets: indices, toOffset: destination)

        let hidden = modules.filter { !$0.isVisible }.sorted { $0.order < $1.order }
        modules = visible + hidden
        normalizeModules()
        modules = modules
        saveModules()
    }
    
    func toggleEditMode() {
        isEditingMode.toggle()
    }
    
    func resetToDefaults() {
        modules = Self.makeDefaultModules()
        normalizeModules()
        saveModules()
    }
    
    func getVisibleModules() -> [DashboardModule] {
        modules.filter { $0.isVisible }.sorted { $0.order < $1.order }
    }
    
    func addModule(_ type: ModuleType, size: ModuleSize) {
        let newOrder = modules.map { $0.order }.max() ?? -1
        let allowedSizes = type.allowedSizes
        let normalizedSize = allowedSizes.contains(size) ? size : (allowedSizes.first ?? .small)
        let newModule = DashboardModule(type: type, size: normalizedSize, order: newOrder + 1, isVisible: true)
        modules.append(newModule)
        normalizeModules()
        modules = modules  // Trigger @Published update
        saveModules()
    }
    
    func removeModule(_ moduleId: String) {
        if let index = modules.firstIndex(where: { $0.id == moduleId }) {
            modules[index].isVisible = false
        }
        normalizeModules()
        modules = modules  // Trigger @Published update
        saveModules()
    }
    
    func deleteAllModules() {
        modules = modules.map { module in
            var updated = module
            updated.isVisible = false
            return updated
        }
        normalizeModules()
        modules = modules  // Trigger @Published update
        saveModules()
    }

    func setModuleVisibility(_ moduleId: String, isVisible: Bool) {
        guard let index = modules.firstIndex(where: { $0.id == moduleId }) else { return }
        modules[index].isVisible = isVisible
        modules = modules
        saveModules()
    }

    func modulesSnapshotForEditor() -> [DashboardModule] {
        modules.sorted { $0.order < $1.order }
    }

    func defaultModulesForEditor() -> [DashboardModule] {
        Self.makeDefaultModules()
    }

    func applyEditorModules(_ updatedModules: [DashboardModule]) {
        modules = updatedModules
        normalizeModules()
        modules = modules
        saveModules()
    }

    private func normalizeModules() {
        modules = modules
            .sorted(by: { $0.order < $1.order })
            .enumerated()
            .map { _, module in
                var module = module
                if !module.type.allowedSizes.contains(module.size) {
                    module.size = module.type.allowedSizes.first ?? .small
                }
                return module
            }

        for index in modules.indices {
            modules[index].order = index
        }
    }
}
