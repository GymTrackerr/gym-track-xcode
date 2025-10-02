//
//  GymTrackerApp.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftUI
import SwiftData

@main
struct GymTrackerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            SplitDay.self,
            Exercise.self,
            ExerciseSplitDay.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
//            ContentView()
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context

    var body: some View {
        ContentView()
//            .environmentObject(TrackerManager(context: context))
            .environmentObject(SplitDayService(context: context))
            .environmentObject(ExerciseService(context: context))
            .environmentObject(ExerciseSplitDayService(context: context))
    }
}
