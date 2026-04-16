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
        let syncMetadataStore = SyncMetadataStore(modelContext: context)
        
        let remoteExerciseRepository = RemoteExerciseRepository()
        let syncHandlers = SyncFeatureRegistry.makeHandlers(
            remoteExerciseRepository: remoteExerciseRepository
        )
        let syncWorker = SyncWorker(
            queueStore: syncQueueStore,
            metadataStore: syncMetadataStore,
            eligibilityService: syncEligibilityService,
            handlers: syncHandlers
        )
        let syncCoordinator = SyncCoordinator(
            queueStore: syncQueueStore,
            eligibilityService: syncEligibilityService,
            worker: syncWorker
        )
        let localExerciseRepository = LocalExerciseRepository(modelContext: context)
        let exerciseRepository = ExerciseSyncRepository(
            localRepository: localExerciseRepository,
            queueStore: syncQueueStore,
            eligibilityService: syncEligibilityService
        )
        let localRoutineRepository = LocalRoutineRepository(modelContext: context)
        let routineRepository = RoutineSyncRepository(
            localRepository: localRoutineRepository,
            queueStore: syncQueueStore,
            eligibilityService: syncEligibilityService
        )
        let localSessionRepository = LocalSessionRepository(modelContext: context)
        let sessionRepository = SessionSyncRepository(
            localRepository: localSessionRepository,
            queueStore: syncQueueStore,
            eligibilityService: syncEligibilityService
        )
        let localUserRepository = LocalUserRepository(modelContext: context)
        let userRepository = UserSyncRepository(
            localRepository: localUserRepository,
            queueStore: syncQueueStore,
            eligibilityService: syncEligibilityService
        )
        let localNutritionRepository = LocalNutritionRepository(modelContext: context)
        let nutritionCatalogRepository = NutritionCatalogSyncRepository(
            localRepository: localNutritionRepository,
            queueStore: syncQueueStore,
            eligibilityService: syncEligibilityService
        )
        let nutritionLogRepository = NutritionLogSyncRepository(
            localRepository: localNutritionRepository,
            queueStore: syncQueueStore,
            eligibilityService: syncEligibilityService
        )
        let nutritionTargetRepository = NutritionTargetSyncRepository(
            localRepository: localNutritionRepository,
            queueStore: syncQueueStore,
            eligibilityService: syncEligibilityService
        )
        let nutritionRepository = ComposedNutritionRepository(
            catalogRepository: nutritionCatalogRepository,
            logRepository: nutritionLogRepository,
            targetRepository: nutritionTargetRepository
        )
        let localHealthKitDailyRepository = LocalHealthKitDailyRepository(modelContext: context)
        let healthKitDailyRepository = HealthKitDailySyncRepository(
            localRepository: localHealthKitDailyRepository,
            queueStore: syncQueueStore,
            eligibilityService: syncEligibilityService
        )

        let exerciseBootstrapCoordinator = ExerciseBootstrapCoordinator(
            localRepository: localExerciseRepository,
            remoteRepository: remoteExerciseRepository
        )

        // Create — no currentUser passed
        let userService = UserService(context: context, repository: userRepository)
        userService.loadFeature()
        let backendAuthService = BackendAuthService(
            eligibilityState: syncEligibilityState,
            bootstrapCoordinator: exerciseBootstrapCoordinator
        )
        
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

        // Service-level sync kickoff hooks run after user binding.
        exerciseService.sync()
        splitDayService.sync()
        sessionService.sync()
        setService.sync()
        exerciseSplitDayService.sync()
        sessionExerciseService.sync()
        nutritionService.sync()
        healthKitDailyStore.sync()
        healthMetricsService.sync()

        syncCoordinator.start()
        syncCoordinator.triggerSync(reason: "serviceSyncKickoff")

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
                timerController: WatchTimerBridge(timerService: timerService)
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
