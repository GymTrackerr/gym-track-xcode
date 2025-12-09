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
    var sharedModelContainer: ModelContainer = SharedModelConfig.createSharedModelContainer()

    @StateObject var userService: UserService
    @StateObject var timerService: TimerService
    @StateObject var exerciseService: ExerciseService
    @StateObject var splitDayService: SplitDayService
    @StateObject var sessionService: SessionService
    @StateObject var setService: SetService
    @StateObject var exerciseSplitDayService: ExerciseSplitDayService
    @StateObject var sessionExerciseService: SessionExerciseService
    
    @StateObject var watchSessionManager: WatchSessionManager
    @StateObject var healthKitManager = HealthKitManager()

    init() {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedModelConfig.appGroupIdentifier) {
            print("iOS - Container Path: \(url)")
            let dbPath = url.appendingPathComponent("gym_tracker.sqlite")
            print("iOS - DB exists: \(FileManager.default.fileExists(atPath: dbPath.path))")
        } else {
            print("iOS - ERROR: Could not access container! Provisioning profile may not have app group capability.")
        }
        
        let context = sharedModelContainer.mainContext

        // Create — no currentUser passed
        let userService = UserService(context: context)
        let timerService = TimerService(context: context)
        let exerciseService = ExerciseService(context: context)
        let splitDayService = SplitDayService(context: context)
        let sessionService = SessionService(context: context)
        let setService = SetService(context: context)
        let exerciseSplitDayService = ExerciseSplitDayService(context: context)
        let sessionExerciseService = SessionExerciseService(context: context)

        // Bind AFTER creation
        timerService.bind(to: userService)
        exerciseService.bind(to: userService)
        splitDayService.bind(to: userService)
        sessionService.bind(to: userService)
        setService.bind(to: userService)
        exerciseSplitDayService.bind(to: userService)
        sessionExerciseService.bind(to: userService)

        self._userService = StateObject(wrappedValue: userService)
        self._timerService = StateObject(wrappedValue: timerService)
        self._exerciseService = StateObject(wrappedValue: exerciseService)
        self._splitDayService = StateObject(wrappedValue: splitDayService)
        self._sessionService = StateObject(wrappedValue: sessionService)
        self._setService = StateObject(wrappedValue: setService)
        self._exerciseSplitDayService = StateObject(wrappedValue: exerciseSplitDayService)
        self._sessionExerciseService = StateObject(wrappedValue: sessionExerciseService)

        self._watchSessionManager = StateObject(
            wrappedValue: WatchSessionManager(
                timerService: timerService,
//                exerciseService: exerciseSvc
            )
        )

    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(healthKitManager)
                .environmentObject(watchSessionManager)
                .environmentObject(userService)
                .environmentObject(splitDayService)
                .environmentObject(exerciseService)
                .environmentObject(exerciseSplitDayService)
                .environmentObject(sessionService)
                .environmentObject(sessionExerciseService)
                .environmentObject(setService)
                .environmentObject(timerService)
        }
        .modelContainer(sharedModelContainer)
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
        }
    }
}
