//
//  SettingsView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-04.
//
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

struct SettingsView: View {
    private enum BackupImportTarget {
        case nutrition
        case exercise
        case appleHealthSummary
    }

    @Environment(\.modelContext) private var context
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var nutritionService: NutritionService
    @EnvironmentObject var exerciseService: ExerciseService
    @EnvironmentObject var splitDayService: RoutineService
    @EnvironmentObject var sessionService: SessionService
    @EnvironmentObject var exerciseSplitDayService: ExerciseSplitDayService
    @EnvironmentObject var sessionExerciseService: SessionExerciseService
    @EnvironmentObject var programService: ProgramService
    @EnvironmentObject var progressionService: ProgressionService
    @EnvironmentObject var healthKitDailyStore: HealthKitDailyStore
    @EnvironmentObject var hkManager: HealthKitManager
    @State private var shareItem: BackupShareItem?
    @State private var showImportPicker = false
    @State private var importTarget: BackupImportTarget = .nutrition
    @State private var exerciseImportMode: ExerciseBackupService.ImportMode = .merge
    @State private var showExportErrorAlert = false
    @State private var backupAlertTitle = "Backup"
    @State private var exportErrorMessage = ""
    @State private var showExerciseTransferTool = false
    @State private var selectedHealthHistoryRange: HealthHistorySyncRange = .defaultSelection
    @State private var isEnablingHealthAccess = false
    @State private var showHealthBackfillPrompt = false
    @State private var backendBaseURLOverride: String = ""
    @State private var exerciseDBBaseURLOverride: String = ""

    var body: some View {
        VStack {
            List {
                HStack {
                    Text("GymTracker Settings")
//                    Spacer()
                }
                // Settings
                // Show Account
                Button {
                    if let currentUserId = userService.currentUser?.id, userService.currentUser?.isDemo != true {
                        userService.removeUser(id: currentUserId)
                    }
                } label: {
                    Text(userService.currentUser?.isDemo == true ? "Delete Account Unavailable for Demo" : "Delete Account")
                }
                .disabled(userService.currentUser?.isDemo == true)

                Section("Accounts") {
                    Button {
                        userService.startNewAccountOnboarding()
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("New Account")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    
                    ForEach(userService.accounts, id: \.id) { account in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(account.name)
                                        .font(.body.weight(.semibold))

                                    if account.isDemo {
                                        AccountChip(title: "Demo", tint: .orange)
                                    }

                                    if userService.currentUser?.id == account.id {
                                        AccountChip(title: "Current", tint: .blue)
                                    }
                                }
                                Text("Last login: \(account.lastLogin, format: .dateTime.month().day().year().hour().minute())")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()

                            if userService.currentUser?.id != account.id {
                                Button("Sign In") {
                                    userService.switchAccount(to: account.id)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                    }
                }

                Section("Account Sync (Optional)") {
                    InteractAccountLinkCard()

                    Toggle(
                        "Enable Remote Sync For This Account",
                        isOn: Binding(
                            get: { userService.currentUser?.remoteSyncEnabled ?? false },
                            set: { userService.setRemoteSyncEnabled($0) }
                        )
                    )
                    .disabled(userService.currentUser?.isDemo == true)
                }

                NavigationLink {
                    DemoSeedView()
                } label: {
                    HStack {
                        Image(systemName: "sparkles.rectangle.stack")
                        Text("Demo Mode")
                    }
                }

                NavigationLink {
                    AboutView()
                } label: {
                    HStack {
                        Image(systemName: "info.circle")
                        Text("About")
                    }
                }
//                NavigationLink {
//
//                }

                NavigationLink {
                    TestDataShow()
                } label: {
                    HStack {
                        Image(systemName: "swiftdata")
                        Text("Debug Data")
                    }
                }

                Section("Preferences") {
                    Toggle("Show Nutrition Tab", isOn: Binding(
                        get: { userService.currentUser?.showNutritionTab ?? true },
                        set: { newValue in
                            userService.setShowNutritionTab(newValue)
                        }
                    ))

                    NavigationLink {
                        TimerFeedbackSettingsView()
                    } label: {
                        HStack {
                            Image(systemName: "bell.badge")
                            Text("Timer Feedback")
                        }
                    }
                }

                Section("Nutrition") {
                    Button {
                        exportNutritionBackup()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export Nutrition Backup")
                        }
                    }

                    Button {
                        importTarget = .nutrition
                        showImportPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Import Nutrition Backup")
                        }
                    }
                }

                Section("Exercises") {
                    Toggle(
                        "Enable ExerciseDB Catalog Sync",
                        isOn: Binding(
                            get: { exerciseService.catalogSyncEnabledForCurrentUser },
                            set: { exerciseService.setCatalogSyncEnabled($0) }
                        )
                    )

                    Button {
                        Task {
                            await exerciseService.syncCatalogNow(force: true)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Sync ExerciseDB Now")
                        }
                    }

                    Button {
                        exportExerciseBackup()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export Exercise Backup")
                        }
                    }

                    Button {
                        exerciseImportMode = .merge
                        importTarget = .exercise
                        showImportPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Import Exercise Backup (Merge)")
                        }
                    }

                    Button {
                        exerciseImportMode = .replace
                        importTarget = .exercise
                        showImportPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Import Exercise Backup (Replace)")
                        }
                    }

                    Button {
                        mergeExercisesWithSameNpId()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.merge")
                            Text("Merge Exercises by npId")
                        }
                    }

                    Button {
                        showExerciseTransferTool = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.left.arrow.right")
                            Text("Transfer History")
                        }
                    }

                }

                Section("Apple Health Access") {
                    Text(healthAccessStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if userService.currentUser?.isDemo == true {
                        Text("Apple Health access is disabled for demo accounts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if userService.currentUser?.allowHealthAccess == true {
                        Button {
                            disableHealthAccessForCurrentUser()
                        } label: {
                            HStack {
                                Image(systemName: "xmark.circle")
                                Text("Disable For This Account")
                            }
                        }
                    } else {
                        Button {
                            Task(priority: .utility) {
                                await enableHealthAccessFromSettings()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "heart.circle")
                                Text(isEnablingHealthAccess ? "Enabling Apple Health..." : "Enable Apple Health Access")
                            }
                        }
                        .disabled(isEnablingHealthAccess)
                    }
                }

                Section("Apple Health Summary") {
                    Picker("History Range", selection: $selectedHealthHistoryRange) {
                        ForEach(HealthHistorySyncRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }

                    Button {
                        triggerSmartPullNow()
                    } label: {
                        HStack {
                            Image(systemName: "bolt.fill")
                            Text("Smart Pull Now")
                        }
                    }
                    .disabled(
                        healthKitDailyStore.isBackfillingHistory ||
                        userService.currentUser?.allowHealthAccess != true ||
                        userService.currentUser?.isDemo == true
                    )

                    Button {
                        triggerFullHealthRefresh()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise.circle")
                            Text("Full Refresh (\(selectedHealthHistoryRange.title))")
                        }
                    }
                    .disabled(
                        healthKitDailyStore.isBackfillingHistory ||
                        userService.currentUser?.allowHealthAccess != true ||
                        userService.currentUser?.isDemo == true
                    )

                    if userService.currentUser?.allowHealthAccess != true {
                        Text("Enable Apple Health access first to use Smart Pull or Full Refresh.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if healthKitDailyStore.isBackfillingHistory {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: healthProgressValue)
                            Text(healthKitDailyStore.backfillStatusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        exportAppleHealthSummaryBackup()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export Apple Health Summary")
                        }
                    }

                    Button {
                        importTarget = .appleHealthSummary
                        showImportPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Import Apple Health Summary")
                        }
                    }
                }

                Section("Developer Networking") {
                    TextField("Backend base URL override", text: $backendBaseURLOverride)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)

                    TextField("ExerciseDB base URL override", text: $exerciseDBBaseURLOverride)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)

                    Button("Apply URL Overrides") {
                        applyNetworkingOverrides()
                    }

                    Button("Clear URL Overrides") {
                        clearNetworkingOverrides()
                    }

                    Text("Leave a field empty to use the normal built-in URL.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .appBackground()
        .navigationTitle("Settings")
        .alert(backupAlertTitle, isPresented: $showExportErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportErrorMessage)
        }
        .confirmationDialog(
            "Pull Apple Health Data Now?",
            isPresented: $showHealthBackfillPrompt,
            titleVisibility: .visible
        ) {
            Button("Smart Pull Now") {
                triggerSmartPullNow()
            }
            Button("Full Refresh (\(selectedHealthHistoryRange.title))") {
                triggerFullHealthRefresh()
            }
            Button("Not Now", role: .cancel) { }
        } message: {
            Text("Health access is enabled for this account. You can start syncing now or do it later from Settings.")
        }
        .onAppear {
            loadSelectedHealthHistoryRangeFromUser()
            loadNetworkingOverrides()
            guard userService.currentUser?.isDemo != true else { return }
            Task(priority: .utility) {
                await hkManager.refreshConnectionState()
            }
        }
        .onChange(of: userService.currentUser?.id) { _, _ in
            loadSelectedHealthHistoryRangeFromUser()
        }
        .onChange(of: selectedHealthHistoryRange) { _, newValue in
            guard userService.currentUser?.isDemo != true else { return }
            userService.setCurrentHealthHistorySyncRange(newValue)
        }
#if os(iOS)
        .sheet(item: $shareItem) { item in
            ActivityShareSheet(activityItems: [item.url])
        }
#endif
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch importTarget {
            case .nutrition:
                handleNutritionImport(result)
            case .exercise:
                handleExerciseImport(result)
            case .appleHealthSummary:
                handleAppleHealthSummaryImport(result)
            }
        }
        .sheet(isPresented: $showExerciseTransferTool) {
            ExerciseTransferToolView()
                .appBackground()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
//        .toolbar {
//            ToolbarItem(placement: .navigationBarTrailing) {
//                Button {
////                    exerciseService.editingExercise = true
//                } label: {
////                    Label("Add Exercise", systemImage: "plus.circle")
//                }
//            }
//        }
    }

    private func exportNutritionBackup() {
        let backupService = NutritionBackupService(
            context: context,
            currentUserProvider: { userService.currentUser }
        )

        do {
            let url = try backupService.exportNutritionJSON()
#if os(iOS)
            shareItem = BackupShareItem(url: url)
#else
            backupAlertTitle = "Export Complete"
            exportErrorMessage = "Backup created at: \(url.path)"
            showExportErrorAlert = true
#endif
        } catch {
            backupAlertTitle = "Couldn’t Export"
            exportErrorMessage = error.localizedDescription
            showExportErrorAlert = true
        }
    }

    private var healthProgressValue: Double {
        guard healthKitDailyStore.backfillProgressTotal > 0 else { return 0 }
        return min(
            max(
                Double(healthKitDailyStore.backfillProgressCompleted) /
                Double(healthKitDailyStore.backfillProgressTotal),
                0
            ),
            1
        )
    }

    private func triggerSmartPullNow() {
        guard let currentUser = userService.currentUser else { return }
        guard currentUser.isDemo != true else { return }
        guard currentUser.allowHealthAccess else { return }

        let userId = currentUser.id.uuidString
        Task(priority: .utility) {
            _ = await healthKitDailyStore.smartPullHealthData(userId: userId)
        }
    }

    private func triggerFullHealthRefresh() {
        guard let currentUser = userService.currentUser else { return }
        guard currentUser.isDemo != true else { return }
        guard currentUser.allowHealthAccess else { return }

        let userId = currentUser.id.uuidString
        let selectedRange = selectedHealthHistoryRange
        Task(priority: .utility) {
            _ = await healthKitDailyStore.fullRefreshHealthHistory(
                userId: userId,
                range: selectedRange
            )
        }
    }

    private var healthAccessStatusText: String {
        if userService.currentUser?.isDemo == true {
            return "Apple Health is unavailable in demo mode."
        }
        if userService.currentUser?.allowHealthAccess == true {
            return hkManager.hkConnected
                ? "Apple Health is enabled for this account."
                : "Enabled for this account, but Apple Health permission appears unavailable right now."
        }
        if hkManager.hkConnected {
            return "Apple Health permission is available on this device, but disabled for this account."
        }
        return "Apple Health is currently disabled for this account."
    }

    @MainActor
    private func enableHealthAccessFromSettings() async {
        guard let targetUserId = userService.currentUser?.id else { return }
        guard userService.currentUser?.isDemo != true else { return }

        isEnablingHealthAccess = true
        defer { isEnablingHealthAccess = false }

        await hkManager.refreshConnectionState()

        if hkManager.hkConnected {
            guard userService.currentUser?.id == targetUserId else { return }
            userService.hkUserAllow(connected: true, requested: true)
            showHealthBackfillPrompt = true
            return
        }

        await hkManager.requestAuthorization()
        guard userService.currentUser?.id == targetUserId else { return }

        userService.hkUserAllow(connected: hkManager.hkConnected, requested: hkManager.hkRequested)

        if userService.currentUser?.allowHealthAccess == true {
            showHealthBackfillPrompt = true
            return
        }

        backupAlertTitle = "Apple Health Access"
        exportErrorMessage = "Permission was not granted. You can enable it in the Health app and try again."
        showExportErrorAlert = true
    }

    private func disableHealthAccessForCurrentUser() {
        guard userService.currentUser?.isDemo != true else { return }
        userService.hkUserAllow(connected: false, requested: false)
    }

    private func loadSelectedHealthHistoryRangeFromUser() {
        selectedHealthHistoryRange = userService.currentHealthHistorySyncRange()
    }

    private func exportExerciseBackup() {
        let backupService = ExerciseBackupService(
            context: context,
            currentUserProvider: { userService.currentUser }
        )

        do {
            let url = try backupService.exportExercisesJSON()
#if os(iOS)
            shareItem = BackupShareItem(url: url)
#else
            backupAlertTitle = "Export Complete"
            exportErrorMessage = "Backup created at: \(url.path)"
            showExportErrorAlert = true
#endif
        } catch {
            backupAlertTitle = "Couldn’t Export"
            exportErrorMessage = error.localizedDescription
            showExportErrorAlert = true
        }
    }

    private func handleNutritionImport(_ result: Result<[URL], any Error>) {
        switch result {
        case .failure(let error):
            backupAlertTitle = "Couldn’t Import"
            exportErrorMessage = error.localizedDescription
            showExportErrorAlert = true
        case .success(let urls):
            guard let url = urls.first else { return }
            let hasSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let backupService = NutritionBackupService(
                context: context,
                currentUserProvider: { userService.currentUser }
            )

            do {
                let imported = try backupService.importNutritionJSON(from: url)
                nutritionService.loadFeature()
                backupAlertTitle = "Import Complete"
                exportErrorMessage = """
                Imported \(imported.foodItems) food items, \(imported.mealRecipes) meal recipes, \(imported.mealRecipeItems) recipe items, and \(imported.nutritionLogEntries) nutrition logs.
                Updated \(imported.targets) nutrition targets.
                """
                showExportErrorAlert = true
            } catch {
                backupAlertTitle = "Couldn’t Import"

                if let backupError = error as? NutritionBackupService.BackupError {
                    switch backupError {
                    case .invalidSchemaVersion:
                        exportErrorMessage = "This backup uses an unsupported nutrition format. Only schemaVersion 2 backups can be imported."
                    default:
                        exportErrorMessage = backupError.localizedDescription
                    }
                } else {
                    exportErrorMessage = error.localizedDescription
                }

                showExportErrorAlert = true
            }
        }
    }

    private func handleExerciseImport(_ result: Result<[URL], any Error>) {
        switch result {
        case .failure(let error):
            backupAlertTitle = "Couldn’t Import"
            exportErrorMessage = error.localizedDescription
            showExportErrorAlert = true
        case .success(let urls):
            guard let url = urls.first else { return }
            let hasSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let backupService = ExerciseBackupService(
                context: context,
                currentUserProvider: { userService.currentUser }
            )

            do {
                let report = try backupService.importExercisesJSON(from: url, mode: exerciseImportMode)
                exerciseService.loadExercises()
                splitDayService.loadSplitDays()
                sessionService.loadSessions()
                exerciseSplitDayService.loadFeature()
                sessionExerciseService.loadFeature()
                programService.loadPrograms()
                progressionService.loadFeature()
                backupAlertTitle = "Import Complete"
                exportErrorMessage = """
                Imported exercises \(report.exercises.inserted + report.exercises.updated), \
                routines \(report.routines.inserted + report.routines.updated), \
                programs \(report.programs.inserted + report.programs.updated), \
                progressions \(report.progressionProfiles.inserted + report.progressionProfiles.updated), \
                sessions \(report.sessions.inserted + report.sessions.updated).
                """
                showExportErrorAlert = true
            } catch {
                backupAlertTitle = "Couldn’t Import"
                exportErrorMessage = error.localizedDescription
                showExportErrorAlert = true
            }
        }
    }

    private func exportAppleHealthSummaryBackup() {
        let transferService = AppleHealthSummaryBackupService(
            context: context,
            currentUserProvider: { userService.currentUser },
            dateNormalizer: HealthKitDateNormalizer()
        )

        do {
            let url = try transferService.exportAppleHealthSummaryJSON()
#if os(iOS)
            shareItem = BackupShareItem(url: url)
#else
            backupAlertTitle = "Export Complete"
            exportErrorMessage = "Backup created at: \\(url.path)"
            showExportErrorAlert = true
#endif
        } catch {
            backupAlertTitle = "Couldn’t Export"
            exportErrorMessage = error.localizedDescription
            showExportErrorAlert = true
        }
    }

    private func handleAppleHealthSummaryImport(_ result: Result<[URL], any Error>) {
        switch result {
        case .failure(let error):
            backupAlertTitle = "Couldn’t Import"
            exportErrorMessage = error.localizedDescription
            showExportErrorAlert = true
        case .success(let urls):
            guard let url = urls.first else { return }
            let hasSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let transferService = AppleHealthSummaryBackupService(
                context: context,
                currentUserProvider: { userService.currentUser },
                dateNormalizer: HealthKitDateNormalizer()
            )

            do {
                let report = try transferService.importAppleHealthSummaryJSON(from: url)
                healthKitDailyStore.notifyExternalSummaryImport()
                backupAlertTitle = "Import Complete"
                exportErrorMessage = """
                Imported \(report.totalImported) day(s): \(report.inserted) inserted, \(report.updated) updated.
                \(report.skipped > 0 ? "Skipped \(report.skipped) invalid/duplicate day(s)." : "")
                """
                showExportErrorAlert = true
            } catch {
                backupAlertTitle = "Couldn’t Import"
                exportErrorMessage = error.localizedDescription
                showExportErrorAlert = true
            }
        }
    }

    private func loadNetworkingOverrides() {
        backendBaseURLOverride = API_Data.backendBaseURLOverride() ?? ""
        exerciseDBBaseURLOverride = API_Data.exerciseDBBaseURLOverride() ?? ""
    }

    private func applyNetworkingOverrides() {
        API_Data.setBackendBaseURLOverride(backendBaseURLOverride)
        API_Data.setExerciseDBBaseURLOverride(exerciseDBBaseURLOverride)
        loadNetworkingOverrides()
    }

    private func clearNetworkingOverrides() {
        API_Data.setBackendBaseURLOverride(nil)
        API_Data.setExerciseDBBaseURLOverride(nil)
        loadNetworkingOverrides()
    }

    private func mergeExercisesWithSameNpId() {
        do {
            let report = try exerciseService.mergeExercisesWithSameNpId()
            splitDayService.loadSplitDays()
            sessionService.loadSessions()
            exerciseSplitDayService.loadFeature()
            sessionExerciseService.loadFeature()

            backupAlertTitle = "Merge Complete"
            exportErrorMessage = "Merged \(report.groupsMerged) npId group(s), removed \(report.duplicatesRemoved) duplicate exercise record(s)."
            showExportErrorAlert = true
        } catch {
            backupAlertTitle = "Merge Failed"
            exportErrorMessage = error.localizedDescription
            showExportErrorAlert = true
        }
    }

}

private struct AccountChip: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct BackupShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

#if os(iOS)
private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
#endif

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack {
                HStack {
                    Text("Nova Productions Project")
                        .fontWeight(.heavy)
                    Spacer()
                }
                HStack {
                    Text("https://novapro.net")
                        .underline()
                    Spacer()
                }
            }
            .padding(20)
            
            VStack {
                HStack {
                    Text("About GymTracker")
                        .fontWeight(.heavy)
                    Spacer()
                }
                HStack {
                    Text("The project was developed by Daniel Kravec at Nova Productions. GymTracker is a fitness app, aimed to make tracking gym sessions easy. It was started in September 2025. It is currently in its alpha phase.")
                    Spacer()
                }
            }
            .padding(20)
            
            VStack {
                HStack {
                    Text("GymTracker Mobile Project")
                        .fontWeight(.heavy)
                    Spacer()
                }
                HStack {
                    Text("Thank you for downloading GymTracker! This version of the application works on macOS, iOS, and iPadOS.")
                    Spacer()
                }
            }
            .padding(20)

            VStack {
                HStack {
                    Text("Version")
                        .fontWeight(.heavy)
                    Spacer()
                }
                HStack {
                    Text("\(appVersion) b\(buildNumber)")
                    Spacer()
                }
            }
            .padding(20)

        }
        .padding(10)
        .navigationTitle("About GymTracker")
    }
    
    // Computed property to get the app version
    var appVersion: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        return "Unknown"
    }

    // Computed property to get the build number
    var buildNumber: String {
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            return build
        }
        return "Unknown"
    }
}

struct TestDataShow : View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject var userService: UserService

    @State var routines: [Routine] = []
    @State var exercises: [Exercise] = []
    @State var ESD: [ExerciseSplitDay] = []
    @State var sessions: [Session] = []
    @State var sessionSets: [SessionSet] = []
    @State var sessionReps: [SessionRep] = []
    @State var sessionEntries: [SessionEntry] = []
    @State var foodItems: [FoodItem] = []
    @State var mealRecipes: [MealRecipe] = []
    @State var mealRecipeItems: [MealRecipeItem] = []
    @State var nutritionLogs: [NutritionLogEntry] = []
    @State var nutritionTargets: [NutritionTarget] = []
    @State var users: [User] = []

    var body: some View {
        List {
            Section("Current Login") {
                if let currentUser = userService.currentUser {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentUser.name)
                            .font(.body.weight(.semibold))
                        Text("\(currentUser.id)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No active user")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Data Point Counts") {
                countRow("Users", total: users.count, current: userService.currentUser == nil ? 0 : 1)
                countRow("Routines", total: routines.count, current: routinesForCurrentUser.count)
                countRow("Exercises", total: exercises.count, current: exercisesForCurrentUser.count)
                countRow("Exercise Split Days", total: ESD.count, current: exerciseSplitsForCurrentUser.count)
                countRow("Sessions", total: sessions.count, current: sessionsForCurrentUser.count)
                countRow("Session Entries", total: sessionEntries.count, current: sessionEntriesForCurrentUser.count)
                countRow("Session Sets", total: sessionSets.count, current: sessionSetsForCurrentUser.count)
                countRow("Session Reps", total: sessionReps.count, current: sessionRepsForCurrentUser.count)
                countRow("Food Items", total: foodItems.count, current: foodItemsForCurrentUser.count)
                countRow("Meal Recipes", total: mealRecipes.count, current: mealRecipesForCurrentUser.count)
                countRow("Meal Recipe Items", total: mealRecipeItems.count, current: mealRecipeItemsForCurrentUser.count)
                countRow("Nutrition Logs", total: nutritionLogs.count, current: nutritionLogsForCurrentUser.count)
                countRow("Nutrition Targets", total: nutritionTargets.count, current: nil)
            }
            Section("Split Days") {
                ForEach(routines, id: \.self) { item in
                    VStack {
                        Text("\(item.id)")
                        Text("\(item.name)")
                    }
                }
            }
            Section("Exercises") {
                ForEach(exercises, id: \.self) { item in
                    VStack {
                        Text("\(item.id)")
                        Text("\(item.name)")
                    }
                }
            }
            Section("Exercises Split Days") {
                ForEach(ESD, id: \.self) { item in
                    VStack {
                        Text("\(item.id)")
                        Text("\(item.routine.name)")
                    }
                }
            }
            Section("Sessions") {
                ForEach(sessions, id: \.self) { item in
                    VStack {
                        Text("\(item.id)")
                    }
                }
            }
            Section("Session Sets") {
                ForEach(sessionSets, id: \.self) { item in
                    VStack {
                        Text("\(item.id)")
                    }
                }
            }
            Section("Session Reps") {
                ForEach(sessionReps, id: \.self) { item in
                    VStack {
                        Text("\(item.id)")
                    }
                }
            }
            Section("Session Entries") {
                ForEach(sessionEntries, id: \.self) { item in
                    VStack {
                        Text("\(item.id)")
                        Text("\(item.exercise.name)")
                    }
                }
            }
            Section("Users") {
                ForEach(users, id: \.id) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(item.id)")
                            Text("\(item.name)")
                        }
                        Spacer()
                        if userService.currentUser?.id == item.id {
                            Text("Current")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Sign In") {
                                userService.switchAccount(to: item.id)
                                reloadDebugData()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }
            }
            Section("Clear Cache") {
                Button {
                    Task {
                        await MediaCache.shared.clearAll()
                    }
                } label: {
                    Text("Clear Media Cache")
                }
            }
            Section("Wipe Data") {
                Button {
                    do {
                        try context.delete(model: SessionRep.self)

                        try context.delete(model: SessionSet.self)

                        
                        try context.delete(model: Routine.self)
                        
                        try context.delete(model: Exercise.self)
                        
                        try context.delete(model: ExerciseSplitDay.self)

                        try context.delete(model: Session.self)
                        try context.delete(model: SessionEntry.self)
                        try context.delete(model: User.self)

                    } catch {
                        print("Failed to clear all data.")
                    }

                } label: {
                    Text("Wipe All Data")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .onAppear() {
            reloadDebugData()
        }
    }

    private var currentUserId: UUID? {
        userService.currentUser?.id
    }

    /// Generic filter helper - filters array based on user ID keypath
    private func filterForCurrentUser<T>(_ items: [T], by keyPath: KeyPath<T, UUID>) -> [T] {
        guard let currentUserId else { return [] }
        return items.filter { $0[keyPath: keyPath] == currentUserId }
    }

    /// Generic filter helper for optional UUID properties
    private func filterForCurrentUser<T>(_ items: [T], by keyPath: KeyPath<T, UUID?>) -> [T] {
        guard let currentUserId else { return [] }
        return items.filter { $0[keyPath: keyPath] == currentUserId }
    }

    private var routinesForCurrentUser: [Routine] {
        filterForCurrentUser(routines, by: \.user_id)
    }

    private var exercisesForCurrentUser: [Exercise] {
        filterForCurrentUser(exercises, by: \.user_id)
    }

    private var exerciseSplitsForCurrentUser: [ExerciseSplitDay] {
        guard let currentUserId else { return [] }
        return ESD.filter { $0.routine.user_id == currentUserId }
    }

    private var sessionsForCurrentUser: [Session] {
        filterForCurrentUser(sessions, by: \.user_id)
    }

    private var sessionEntriesForCurrentUser: [SessionEntry] {
        guard let currentUserId else { return [] }
        return sessionEntries.filter { $0.session.user_id == currentUserId }
    }

    private var sessionSetsForCurrentUser: [SessionSet] {
        guard let currentUserId else { return [] }
        return sessionSets.filter { $0.sessionEntry.session.user_id == currentUserId }
    }

    private var sessionRepsForCurrentUser: [SessionRep] {
        guard let currentUserId else { return [] }
        return sessionReps.filter { $0.sessionSet.sessionEntry.session.user_id == currentUserId }
    }

    private var foodItemsForCurrentUser: [FoodItem] {
        filterForCurrentUser(foodItems, by: \.userId)
    }

    private var mealRecipesForCurrentUser: [MealRecipe] {
        filterForCurrentUser(mealRecipes, by: \.userId)
    }

    private var mealRecipeItemsForCurrentUser: [MealRecipeItem] {
        guard let currentUserId else { return [] }
        return mealRecipeItems.filter { $0.mealRecipe?.userId == currentUserId }
    }

    private var nutritionLogsForCurrentUser: [NutritionLogEntry] {
        filterForCurrentUser(nutritionLogs, by: \.userId)
    }

    @ViewBuilder
    private func countRow(_ label: String, total: Int, current: Int?) -> some View {
        HStack {
            Text(label)
            Spacer()
            if let current {
                Text("all \(total) | current \(current)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                Text("all \(total)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }

    private func reloadDebugData() {
        routines = try! context.fetch(FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.timestamp)]))
        exercises = try! context.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.timestamp)]))
        ESD = try! context.fetch(FetchDescriptor<ExerciseSplitDay>(sortBy: [SortDescriptor(\.id)]))

        sessions = try! context.fetch(FetchDescriptor<Session>(sortBy: [SortDescriptor(\.timestamp)]))
        sessionSets = try! context.fetch(FetchDescriptor<SessionSet>(sortBy: [SortDescriptor(\.timestamp)]))
        sessionReps = try! context.fetch(FetchDescriptor<SessionRep>(sortBy: [SortDescriptor(\.id)]))
        sessionEntries = try! context.fetch(FetchDescriptor<SessionEntry>(sortBy: [SortDescriptor(\.id)]))

        foodItems = try! context.fetch(FetchDescriptor<FoodItem>(sortBy: [SortDescriptor(\.createdAt)]))
        mealRecipes = try! context.fetch(FetchDescriptor<MealRecipe>(sortBy: [SortDescriptor(\.createdAt)]))
        mealRecipeItems = try! context.fetch(FetchDescriptor<MealRecipeItem>(sortBy: [SortDescriptor(\.id)]))
        nutritionLogs = try! context.fetch(FetchDescriptor<NutritionLogEntry>(sortBy: [SortDescriptor(\.timestamp)]))
        nutritionTargets = try! context.fetch(FetchDescriptor<NutritionTarget>(sortBy: [SortDescriptor(\.createdAt)]))

        users = try! context.fetch(FetchDescriptor<User>(sortBy: [SortDescriptor(\.lastLogin, order: .reverse)]))
    }
}
