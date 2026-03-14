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
    @StateObject var dashboardService: DashboardService
    @StateObject var timerService: TimerService
    @StateObject var exerciseService: ExerciseService
    @StateObject var splitDayService: RoutineService
    @StateObject var sessionService: SessionService
    @StateObject var setService: SetService
    @StateObject var exerciseSplitDayService: ExerciseSplitDayService
    @StateObject var sessionExerciseService: SessionExerciseService
    @StateObject var nutritionService: NutritionService
    @StateObject var programService: ProgramService
    @StateObject var progressionEvaluationService: ProgressionEvaluationService
    
    @StateObject var watchSessionManager: WatchSessionManager
    @StateObject var healthKitManager = HealthKitManager()
    @StateObject var toastManager = ActionToastManager()

    init() {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedModelConfig.appGroupIdentifier) {
            print("iOS - Container Path: \(url)")
            let dbPath = url.appendingPathComponent("gym_tracker.sqlite")
            print("iOS - DB exists: \(FileManager.default.fileExists(atPath: dbPath.path))")
        } else {
            print("iOS - ERROR: Could not access container! Provisioning profile may not have app group capability.")
        }
        
        let context = sharedModelContainer.mainContext
        LegacyStoreRecoveryService.recoverIfNeeded(destinationContext: context)

        // Create — no currentUser passed
        let userService = UserService(context: context)
        userService.loadFeature()
        
        let dashboardService = DashboardService(context: context)
        let timerService = TimerService(context: context)
        let exerciseService = ExerciseService(context: context)
        let splitDayService = RoutineService(context: context)
        let sessionService = SessionService(context: context)
        let setService = SetService(context: context)
        let exerciseSplitDayService = ExerciseSplitDayService(context: context)
        let sessionExerciseService = SessionExerciseService(context: context)
        let nutritionService = NutritionService(context: context)
        let programService = ProgramService(context: context)
        let progressionEvaluationService = ProgressionEvaluationService(context: context)

        // Bind AFTER creation
        dashboardService.bind(to: userService)
        timerService.bind(to: userService)
        exerciseService.bind(to: userService)
        splitDayService.bind(to: userService)
        sessionService.bind(to: userService)
        setService.bind(to: userService)
        exerciseSplitDayService.bind(to: userService)
        sessionExerciseService.bind(to: userService)
        nutritionService.bind(to: userService)
        programService.bind(to: userService)
        progressionEvaluationService.bind(to: userService)

        self._dashboardService = StateObject(wrappedValue: dashboardService)
        self._userService = StateObject(wrappedValue: userService)
        self._timerService = StateObject(wrappedValue: timerService)
        self._exerciseService = StateObject(wrappedValue: exerciseService)
        self._splitDayService = StateObject(wrappedValue: splitDayService)
        self._sessionService = StateObject(wrappedValue: sessionService)
        self._setService = StateObject(wrappedValue: setService)
        self._exerciseSplitDayService = StateObject(wrappedValue: exerciseSplitDayService)
        self._sessionExerciseService = StateObject(wrappedValue: sessionExerciseService)
        self._nutritionService = StateObject(wrappedValue: nutritionService)
        self._programService = StateObject(wrappedValue: programService)
        self._progressionEvaluationService = StateObject(wrappedValue: progressionEvaluationService)

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
                .overlay(alignment: .top) {
                    ActionToastStack()
                }
                .environmentObject(toastManager)
                .environmentObject(healthKitManager)
                .environmentObject(watchSessionManager)
                .environmentObject(userService)
                .environmentObject(dashboardService)
                .environmentObject(splitDayService)
                .environmentObject(exerciseService)
                .environmentObject(exerciseSplitDayService)
                .environmentObject(sessionService)
                .environmentObject(sessionExerciseService)
                .environmentObject(setService)
                .environmentObject(timerService)
                .environmentObject(nutritionService)
                .environmentObject(programService)
                .environmentObject(progressionEvaluationService)
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
