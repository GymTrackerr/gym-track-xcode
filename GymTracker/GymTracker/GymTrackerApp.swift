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
            Item.self,
            SplitDay.self,
            Exercise.self,
            ExerciseSplitDay.self,
            User.self,
            Session.self
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
            ParentRootView()
//                .environmentObject(UserService(context: context, currentUser: nil))
        }
        .modelContainer(sharedModelContainer)
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
        if (userService.accountCreated == false) {
            OnBoardView()
        } else {
            ContentView()
                .environmentObject(SplitDayService(context: context, currentUser: userService.currentUser))
                .environmentObject(ExerciseService(context: context, currentUser: userService.currentUser))
                .environmentObject(ExerciseSplitDayService(context: context, currentUser: userService.currentUser))
                .environmentObject(SessionService(context: context, currentUser: userService.currentUser))
        }
    }
}
