//
//  SharedModelConfig.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-12-07.
//

import SwiftData
import Foundation

struct SharedModelConfig {
    static let appGroupIdentifier = "group.net.novapro.GymTracker"
    static let schema = Schema([
        User.self,
        SyncMetadataItem.self,
        SyncQueueItem.self,
        Exercise.self,
        Session.self,
        SessionEntry.self,
        SessionSet.self,
        SessionRep.self,
        Routine.self,
        ExerciseSplitDay.self,
        TrackerTimer.self,
        Food.self,
        FoodLog.self,
        Meal.self,
        MealItem.self,
        MealEntry.self,
        NutritionTarget.self,
        FoodItem.self,
        MealRecipe.self,
        MealRecipeItem.self,
        NutritionLogEntry.self,
        HealthKitDailyAggregateData.self,
        DemoSeedProfile.self
    ])
    
    static func createSharedModelContainer() -> ModelContainer {
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            url: containerURL()
        )
        
        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
#if DEBUG
            let configuredStoreURL = modelConfiguration.url.absoluteString
            let resolvedStoreURLs = container.configurations.map { $0.url.absoluteString }
            print("SwiftData configured store URL: \(configuredStoreURL)")
            print("SwiftData resolved store URLs: \(resolvedStoreURLs)")
#endif
            return container
        } catch {
#if DEBUG
            fatalError("ModelContainer initialization failed. Refusing to reset/fallback in DEBUG to avoid silent data loss. Error: \(error)")
#else
            fatalError("Could not create shared ModelContainer: \(error)")
#endif
        }
    }

    static func createLegacyModelContainer() throws -> ModelContainer {
        let legacyConfiguration = ModelConfiguration(schema: schema)
        return try ModelContainer(for: schema, configurations: [legacyConfiguration])
    }
    
    private static func containerURL() -> URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            fatalError("Could not get shared container URL for app group: \(appGroupIdentifier)")
        }
        return url.appendingPathComponent("gym_tracker.sqlite")
    }
}
