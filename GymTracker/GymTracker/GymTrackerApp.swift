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
    @Environment(\.modelContext) private var context

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SplitDay.self,
            Exercise.self,
            ExerciseSplitDay.self,
            User.self,
            Session.self,
            SessionExercise.self,
            SessionSet.self,
            SessionRep.self
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
            ParentRootView()
        }
        .modelContainer(sharedModelContainer)
    }
    
    init() {
        print(URL.applicationSupportDirectory.path(percentEncoded: false))
    }
}

struct ParentRootView: View {
    @Environment(\.modelContext) private var context
//    @EnvironmentObject var userService: UserService

    var body: some View {
        RootView()
            .environmentObject(UserService(context: context, currentUser: nil))

    }
}
struct RootView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject var userService: UserService

    var body: some View {
        if (userService.onBoarding == true) {
            OnBoardView()
        } else {
            ContentView()
                .environmentObject(HealthKitManager())
                .environmentObject(SplitDayService(context: context, currentUser: userService.currentUser))
                .environmentObject(ExerciseService(context: context, currentUser: userService.currentUser))
                .environmentObject(ExerciseSplitDayService(context: context, currentUser: userService.currentUser))
                .environmentObject(SessionService(context: context, currentUser: userService.currentUser))
                .environmentObject(SessionExerciseService(context: context, currentUser: userService.currentUser))
                .environmentObject(SetService(context: context, currentUser: userService.currentUser))
        }
    }
}
