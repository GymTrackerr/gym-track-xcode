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
    @StateObject var backendAuthService: BackendAuthService
    @StateObject var syncEligibilityState: SyncEligibilityState
    @StateObject var syncEligibilityService: SyncEligibilityService
    @StateObject var syncCoordinator: SyncCoordinator
    @StateObject var dashboardService: DashboardService
    @StateObject var timerService: TimerService
    @StateObject var exerciseService: ExerciseService
    @StateObject var splitDayService: RoutineService
    @StateObject var sessionService: SessionService
    @StateObject var setService: SetService
    @StateObject var exerciseSplitDayService: ExerciseSplitDayService
    @StateObject var sessionExerciseService: SessionExerciseService
    @StateObject var nutritionService: NutritionService
    
    @StateObject var watchSessionManager: WatchSessionManager
    @StateObject var healthKitManager: HealthKitManager
    @StateObject var healthKitDailyStore: HealthKitDailyStore
    @StateObject var healthMetricsService: HealthMetricsService
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
        let syncEligibilityState = SyncEligibilityState()
        let syncEligibilityService = SyncEligibilityService(eligibilityState: syncEligibilityState)
        let syncQueueStore = SyncQueueStore(modelContext: context)
        let syncWorker = SyncWorker(queueStore: syncQueueStore)
        let syncCoordinator = SyncCoordinator(
            queueStore: syncQueueStore,
            eligibilityService: syncEligibilityService,
            worker: syncWorker
        )
        let exerciseRepository = LocalExerciseRepository(
            modelContext: context,
            queueStore: syncQueueStore,
            eligibilityService: syncEligibilityService
        )
        let routineRepository = LocalRoutineRepository(modelContext: context)
        let sessionRepository = LocalSessionRepository(modelContext: context)
        let userRepository = LocalUserRepository(modelContext: context)
        let nutritionRepository = LocalNutritionRepository(modelContext: context)
        let healthKitDailyRepository = LocalHealthKitDailyRepository(modelContext: context)

        // Create — no currentUser passed
        let userService = UserService(context: context, repository: userRepository)
        userService.loadFeature()
        let backendAuthService = BackendAuthService(eligibilityState: syncEligibilityState)
        
        let dashboardService = DashboardService(context: context)
        let timerService = TimerService(context: context)
        let exerciseService = ExerciseService(context: context, repository: exerciseRepository)
        let splitDayService = RoutineService(context: context, repository: routineRepository)
        let sessionService = SessionService(context: context, repository: sessionRepository)
        let setService = SetService(context: context, repository: sessionRepository)
        let exerciseSplitDayService = ExerciseSplitDayService(context: context, repository: routineRepository)
        let sessionExerciseService = SessionExerciseService(context: context, repository: sessionRepository)
        let nutritionService = NutritionService(context: context, repository: nutritionRepository)
        let healthKitManager = HealthKitManager()
        let healthKitDateNormalizer = HealthKitDateNormalizer()
        let healthKitDailyStore = HealthKitDailyStore(
            context: context,
            repository: healthKitDailyRepository,
            healthKitManager: healthKitManager,
            dateNormalizer: healthKitDateNormalizer
        )
        let healthMetricsService = HealthMetricsService(
            context: context,
            dailyStore: healthKitDailyStore,
            nutritionService: nutritionService,
            dateNormalizer: healthKitDateNormalizer
        )

        // Bind AFTER creation
        backendAuthService.bind(to: userService)
        dashboardService.bind(to: userService)
        timerService.bind(to: userService)
        exerciseService.bind(to: userService)
        splitDayService.bind(to: userService)
        sessionService.bind(to: userService)
        setService.bind(to: userService)
        exerciseSplitDayService.bind(to: userService)
        sessionExerciseService.bind(to: userService)
        nutritionService.bind(to: userService)
        healthKitDailyStore.bind(to: userService)
        healthMetricsService.bind(to: userService)
        syncCoordinator.start()

        self._dashboardService = StateObject(wrappedValue: dashboardService)
        self._userService = StateObject(wrappedValue: userService)
        self._backendAuthService = StateObject(wrappedValue: backendAuthService)
        self._syncEligibilityState = StateObject(wrappedValue: syncEligibilityState)
        self._syncEligibilityService = StateObject(wrappedValue: syncEligibilityService)
        self._syncCoordinator = StateObject(wrappedValue: syncCoordinator)
        self._timerService = StateObject(wrappedValue: timerService)
        self._exerciseService = StateObject(wrappedValue: exerciseService)
        self._splitDayService = StateObject(wrappedValue: splitDayService)
        self._sessionService = StateObject(wrappedValue: sessionService)
        self._setService = StateObject(wrappedValue: setService)
        self._exerciseSplitDayService = StateObject(wrappedValue: exerciseSplitDayService)
        self._sessionExerciseService = StateObject(wrappedValue: sessionExerciseService)
        self._nutritionService = StateObject(wrappedValue: nutritionService)
        self._healthKitManager = StateObject(wrappedValue: healthKitManager)
        self._healthKitDailyStore = StateObject(wrappedValue: healthKitDailyStore)
        self._healthMetricsService = StateObject(wrappedValue: healthMetricsService)

        self._watchSessionManager = StateObject(
            wrappedValue: WatchSessionManager(
                timerController: WatchTimerBridge(timerService: timerService),
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
                .environmentObject(healthKitDailyStore)
                .environmentObject(healthMetricsService)
                .environmentObject(watchSessionManager)
                .environmentObject(userService)
                .environmentObject(backendAuthService)
                .environmentObject(syncEligibilityState)
                .environmentObject(syncEligibilityService)
                .environmentObject(syncCoordinator)
                .environmentObject(dashboardService)
                .environmentObject(splitDayService)
                .environmentObject(exerciseService)
                .environmentObject(exerciseSplitDayService)
                .environmentObject(sessionService)
                .environmentObject(sessionExerciseService)
                .environmentObject(setService)
                .environmentObject(timerService)
                .environmentObject(nutritionService)
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
