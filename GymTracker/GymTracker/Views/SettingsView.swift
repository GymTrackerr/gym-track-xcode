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
    }

    @Environment(\.modelContext) private var context
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var nutritionService: NutritionService
    @EnvironmentObject var exerciseService: ExerciseService
    @EnvironmentObject var splitDayService: RoutineService
    @EnvironmentObject var sessionService: SessionService
    @EnvironmentObject var exerciseSplitDayService: ExerciseSplitDayService
    @EnvironmentObject var sessionExerciseService: SessionExerciseService
    @State private var shareItem: BackupShareItem?
    @State private var showImportPicker = false
    @State private var importTarget: BackupImportTarget = .nutrition
    @State private var exerciseImportMode: ExerciseBackupService.ImportMode = .merge
    @State private var showExportErrorAlert = false
    @State private var backupAlertTitle = "Backup"
    @State private var exportErrorMessage = ""

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
                    userService.removeUser(id: userService.currentUser!.id)
                } label: {
                    Text("Delete Account")
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

                }
            }
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
            }
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
                exportErrorMessage = "Imported \(imported.foods) foods, \(imported.meals) meals, \(imported.foodLogs) logs."
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

    @State var routines: [Routine] = []
    @State var exercises: [Exercise] = []
    @State var ESD: [ExerciseSplitDay] = []
    @State var sessions: [Session] = []
    @State var sessionSets: [SessionSet] = []
    @State var sessionReps: [SessionRep] = []
    @State var sessionEntries: [SessionEntry] = []
    @State var users: [User] = []

    var body: some View {
        List {
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
                ForEach(users, id: \.self) { item in
                    VStack {
                        Text("\(item.id)")
                        Text("\(item.name)")
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
        .onAppear() {
            routines = try! context.fetch(FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.timestamp)]))
            exercises = try! context.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.timestamp)]))
            ESD = try! context.fetch(FetchDescriptor<ExerciseSplitDay>(sortBy: [SortDescriptor(\.id)]))
            
            sessions = try! context.fetch(FetchDescriptor<Session>(sortBy: [SortDescriptor(\.timestamp)]))
            sessionSets = try! context.fetch(FetchDescriptor<SessionSet>(sortBy: [SortDescriptor(\.timestamp)]))
            sessionReps = try! context.fetch(FetchDescriptor<SessionRep>(sortBy: [SortDescriptor(\.id)]))
            
            sessionEntries = try! context.fetch(FetchDescriptor<SessionEntry>(sortBy: [SortDescriptor(\.id)]))
            
            users = try! context.fetch(FetchDescriptor<User>(sortBy: [SortDescriptor(\.lastLogin)]))

        }
    }
}
