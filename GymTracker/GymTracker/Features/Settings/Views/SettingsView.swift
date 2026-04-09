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
    @EnvironmentObject var healthKitDailyStore: HealthKitDailyStore
    @State private var shareItem: BackupShareItem?
    @State private var showImportPicker = false
    @State private var importTarget: BackupImportTarget = .nutrition
    @State private var exerciseImportMode: ExerciseBackupService.ImportMode = .merge
    @State private var showExportErrorAlert = false
    @State private var backupAlertTitle = "Backup"
    @State private var exportErrorMessage = ""
    @State private var showExerciseTransferTool = false
    @State private var newUserName: String = ""

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
                    if let currentUserId = userService.currentUser?.id {
                        userService.removeUser(id: currentUserId)
                    }
                } label: {
                    Text("Delete Account")
                }

                Section("Accounts") {
                    HStack {
                        TextField("New username", text: $newUserName)
                            .textFieldStyle(.roundedBorder)
                        Button("Create") {
                            if !newUserName.trimmingCharacters(in: .whitespaces).isEmpty {
                                userService.addUser(text: newUserName)
                                newUserName = ""
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newUserName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    
                    ForEach(userService.accounts, id: \.id) { account in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(account.name)
                                    .font(.body.weight(.semibold))
                                Text("Last login: \(account.lastLogin, format: .dateTime.month().day().year().hour().minute())")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()

                            if userService.currentUser?.id == account.id {
                                Text("Current")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            } else {
                                Button("Sign In") {
                                    userService.switchAccount(to: account.id)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
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
                    Button {
                        Task {
                            await exerciseService.refreshApiExercisesWithoutInsert()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh API Exercises (No Inserts)")
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

                Section("Apple Health Summary") {
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
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
        .alert(backupAlertTitle, isPresented: $showExportErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportErrorMessage)
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
                Imported legacy: \(imported.foods) foods, \(imported.meals) meals, \(imported.foodLogs) logs.
                Imported v2: \(imported.foodItems) food items, \(imported.mealRecipes) meal recipes, \(imported.nutritionLogEntries) nutrition logs.
                """
                showExportErrorAlert = true
            } catch {
                backupAlertTitle = "Couldn’t Import"
                exportErrorMessage = error.localizedDescription
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
                backupAlertTitle = "Import Complete"
                exportErrorMessage = """
                Imported exercises \(report.exercises.inserted + report.exercises.updated), \
                routines \(report.routines.inserted + report.routines.updated), \
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
    @State var foods: [Food] = []
    @State var foodLogs: [FoodLog] = []
    @State var meals: [Meal] = []
    @State var mealEntries: [MealEntry] = []
    @State var mealItems: [MealItem] = []
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
                countRow("Foods", total: foods.count, current: foodsForCurrentUser.count)
                countRow("Food Logs", total: foodLogs.count, current: foodLogsForCurrentUser.count)
                countRow("Meals", total: meals.count, current: mealsForCurrentUser.count)
                countRow("Meal Entries", total: mealEntries.count, current: mealEntriesForCurrentUser.count)
                countRow("Meal Items", total: mealItems.count, current: mealItemsForCurrentUser.count)
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

    private var foodsForCurrentUser: [Food] {
        filterForCurrentUser(foods, by: \.userId)
    }

    private var foodLogsForCurrentUser: [FoodLog] {
        filterForCurrentUser(foodLogs, by: \.userId)
    }

    private var mealsForCurrentUser: [Meal] {
        filterForCurrentUser(meals, by: \.userId)
    }

    private var mealEntriesForCurrentUser: [MealEntry] {
        filterForCurrentUser(mealEntries, by: \.userId)
    }

    private var mealItemsForCurrentUser: [MealItem] {
        guard let currentUserId else { return [] }
        return mealItems.filter { $0.meal?.userId == currentUserId }
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

        foods = try! context.fetch(FetchDescriptor<Food>(sortBy: [SortDescriptor(\.createdAt)]))
        foodLogs = try! context.fetch(FetchDescriptor<FoodLog>(sortBy: [SortDescriptor(\.timestamp)]))
        meals = try! context.fetch(FetchDescriptor<Meal>(sortBy: [SortDescriptor(\.createdAt)]))
        mealEntries = try! context.fetch(FetchDescriptor<MealEntry>(sortBy: [SortDescriptor(\.timestamp)]))
        mealItems = try! context.fetch(FetchDescriptor<MealItem>(sortBy: [SortDescriptor(\.id)]))
        nutritionTargets = try! context.fetch(FetchDescriptor<NutritionTarget>(sortBy: [SortDescriptor(\.createdAt)]))

        users = try! context.fetch(FetchDescriptor<User>(sortBy: [SortDescriptor(\.lastLogin, order: .reverse)]))
    }
}
