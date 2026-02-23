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
    
    static func createSharedModelContainer() -> ModelContainer {
        let schema = Schema([
            User.self,
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
            MealEntry.self
        ])
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            url: containerURL()
        )
        
        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            return container
        } catch {
            fatalError("Could not create shared ModelContainer: \(error)")
        }
    }
    
    private static func containerURL() -> URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            fatalError("Could not get shared container URL for app group: \(appGroupIdentifier)")
        }
        return url.appendingPathComponent("gym_tracker.sqlite")
    }
}
