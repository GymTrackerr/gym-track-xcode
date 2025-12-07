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
    var sharedModelContainer: ModelContainer = 
        SharedModelConfig.createSharedModelContainer()

    var body: some Scene {
        WindowGroup {
            ParentRootView()
        }
        .modelContainer(sharedModelContainer)
    }
    
    init() {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedModelConfig.appGroupIdentifier) {
            print("Container Path: \(url)")
        }
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
                .environmentObject(TimerService(context: context, currentUser: userService.currentUser))

        }
    }
}
