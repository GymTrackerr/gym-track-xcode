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
    @StateObject var programService: ProgramService
    @StateObject var sessionService: SessionService
    @StateObject var setService: SetService
    @StateObject var exerciseSplitDayService: ExerciseSplitDayService
    @StateObject var sessionExerciseService: SessionExerciseService
    @StateObject var progressionService: ProgressionService
    @StateObject var nutritionService: NutritionService
    
    @StateObject var watchSessionManager: WatchSessionManager
    @StateObject var healthKitManager: HealthKitManager
    @StateObject var healthKitDailyStore: HealthKitDailyStore
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
        let localProgramRepository = LocalProgramRepository(modelContext: context)
        let programRepository = ProgramSyncRepository(
            localRepository: localProgramRepository,
            queueStore: syncQueueStore,
            eligibilityService: syncEligibilityService
        )
        let localSessionRepository = LocalSessionRepository(modelContext: context)
        let sessionRepository = SessionSyncRepository(
            localRepository: localSessionRepository,
            queueStore: syncQueueStore,
            eligibilityService: syncEligibilityService
        )
        let localProgressionRepository = LocalProgressionRepository(modelContext: context)
        let progressionRepository = ProgressionSyncRepository(
            localRepository: localProgressionRepository,
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
        let programService = ProgramService(context: context, repository: programRepository)
        let sessionService = SessionService(context: context, repository: sessionRepository)
        let setService = SetService(context: context, repository: sessionRepository)
        let exerciseSplitDayService = ExerciseSplitDayService(context: context, repository: routineRepository)
        let sessionExerciseService = SessionExerciseService(context: context, repository: sessionRepository)
        let progressionService = ProgressionService(
            context: context,
            repository: progressionRepository,
            historyRepository: sessionRepository
        )
        let nutritionService = NutritionService(context: context, repository: nutritionRepository)
        let healthKitManager = HealthKitManager()
        let healthKitDateNormalizer = HealthKitDateNormalizer()
        let healthKitDailyStore = HealthKitDailyStore(
            context: context,
            repository: healthKitDailyRepository,
            healthKitManager: healthKitManager,
            dateNormalizer: healthKitDateNormalizer
        )

        // Bind AFTER creation
        backendAuthService.bind(to: userService)
        dashboardService.bind(to: userService)
        timerService.bind(to: userService)
        exerciseService.bind(to: userService)
        splitDayService.bind(to: userService)
        programService.bind(to: userService)
        sessionService.bind(to: userService)
        setService.bind(to: userService)
        exerciseSplitDayService.bind(to: userService)
        sessionExerciseService.bind(to: userService)
        progressionService.bind(to: userService)
        nutritionService.bind(to: userService)
        healthKitDailyStore.bind(to: userService)

        sessionService.progressionService = progressionService
        sessionService.programService = programService
        sessionExerciseService.progressionService = progressionService

        // Service-level sync kickoff hooks run after user binding.
        exerciseService.sync()
        splitDayService.sync()
        programService.sync()
        sessionService.sync()
        setService.sync()
        exerciseSplitDayService.sync()
        sessionExerciseService.sync()
        progressionService.sync()
        nutritionService.sync()
        healthKitDailyStore.sync()

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
        self._programService = StateObject(wrappedValue: programService)
        self._sessionService = StateObject(wrappedValue: sessionService)
        self._setService = StateObject(wrappedValue: setService)
        self._exerciseSplitDayService = StateObject(wrappedValue: exerciseSplitDayService)
        self._sessionExerciseService = StateObject(wrappedValue: sessionExerciseService)
        self._progressionService = StateObject(wrappedValue: progressionService)
        self._nutritionService = StateObject(wrappedValue: nutritionService)
        self._healthKitManager = StateObject(wrappedValue: healthKitManager)
        self._healthKitDailyStore = StateObject(wrappedValue: healthKitDailyStore)

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
                .environmentObject(watchSessionManager)
                .environmentObject(userService)
                .environmentObject(backendAuthService)
                .environmentObject(syncEligibilityState)
                .environmentObject(syncEligibilityService)
                .environmentObject(syncCoordinator)
                .environmentObject(dashboardService)
                .environmentObject(splitDayService)
                .environmentObject(programService)
                .environmentObject(exerciseService)
                .environmentObject(exerciseSplitDayService)
                .environmentObject(sessionService)
                .environmentObject(sessionExerciseService)
                .environmentObject(setService)
                .environmentObject(timerService)
                .environmentObject(progressionService)
                .environmentObject(nutritionService)
        }
        .modelContainer(sharedModelContainer)
    }
    
}

struct RootView: View {
    @EnvironmentObject var userService: UserService
    
    var body: some View {
        if userService.onboardingState != nil {
            OnboardingRootView()
                .environment(\.locale, userService.currentLanguagePreference.effectiveLocale)
                .preferredColorScheme(userService.currentAppearancePreference.colorScheme)
        } else {
            ContentView()
                .environment(\.locale, userService.currentLanguagePreference.effectiveLocale)
                .preferredColorScheme(userService.currentAppearancePreference.colorScheme)
        }
    }
}
