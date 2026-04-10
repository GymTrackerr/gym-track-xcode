import Foundation
import SwiftUI
import Combine
//import CoreData

class DashboardService: ServiceBase, ObservableObject {
    @Published var modules: [DashboardModule] = []
    @Published var isEditingMode: Bool = false
    
    private let userDefaults = UserDefaults.standard
    private let modulesKey = "dashboardModules"
    
    override func loadFeature() {
        loadModules()
        if modules.isEmpty {
            loadDefaultModules()
        }
    }
    
    // MARK: - Default Configuration
    private func loadDefaultModules() {
        let defaultModules = [
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
        
        self.modules = defaultModules
        saveModules()
    }
    
    // MARK: - Persistence
    func saveModules() {
        do {
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
            modules.sort { $0.order < $1.order }
            print("Loaded \(modules.count) modules from UserDefaults")
        } catch {
            print("Failed to load modules: \(error), will create defaults")
        }
        
    }
    
    // MARK: - Module Management
    func updateModule(_ module: DashboardModule) {
        if let index = modules.firstIndex(where: { $0.id == module.id }) {
            modules[index] = module
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
            modules[index].size = newSize
            modules = modules  // Trigger @Published update
            saveModules()
        }
    }
    
    func reorderModules(_ indices: IndexSet, with source: Int) {
        modules.move(fromOffsets: indices, toOffset: source)
        for (index, _) in modules.enumerated() {
            modules[index].order = index
        }
        modules = modules  // Trigger @Published update
        saveModules()
    }
    
    func toggleEditMode() {
        isEditingMode.toggle()
    }
    
    func resetToDefaults() {
        let defaultModules = [
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
        modules = defaultModules
        saveModules()
    }
    
    func getVisibleModules() -> [DashboardModule] {
        modules.filter { $0.isVisible }.sorted { $0.order < $1.order }
    }
    
    func addModule(_ type: ModuleType, size: ModuleSize) {
        let newOrder = modules.map { $0.order }.max() ?? -1
        let newModule = DashboardModule(type: type, size: size, order: newOrder + 1, isVisible: true)
        modules.append(newModule)
        modules = modules  // Trigger @Published update
        saveModules()
    }
    
    func removeModule(_ moduleId: String) {
        modules.removeAll { $0.id == moduleId }
        // Reorder remaining modules
        for (index, _) in modules.enumerated() {
            modules[index].order = index
        }
        modules = modules  // Trigger @Published update
        saveModules()
    }
    
    func deleteAllModules() {
        modules.removeAll()
        modules = modules  // Trigger @Published update
        saveModules()
    }
}
