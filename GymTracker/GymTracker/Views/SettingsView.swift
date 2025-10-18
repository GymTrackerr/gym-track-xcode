//
//  SettingsView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-04.
//
import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject var userService: UserService

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

                NavigationLink {
                    TestDataShow()
                } label: {
                    HStack {
                        Image(systemName: "swiftdata")
                        Text("Debug Data")
                    }
                }
            }
        }
        .navigationTitle("Settings")
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
}

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

    @State var splitDays: [SplitDay] = []
    @State var exercises: [Exercise] = []
    @State var ESD: [ExerciseSplitDay] = []
    @State var sessions: [Session] = []
    @State var sessionSets: [SessionSet] = []
    @State var sessionReps: [SessionRep] = []
    @State var sessionExercises: [SessionExercise] = []
    @State var users: [User] = []

    var body: some View {
        List {
            Section("Split Days") {
                ForEach(splitDays, id: \.self) { item in
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
                        Text("\(item.splitDay.name)")
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
            Section("Session Exercises") {
                ForEach(sessionExercises, id: \.self) { item in
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
            Section("Wipe Data") {
                Button {
                    do {
                        try context.delete(model: ExerciseSplitDay.self)
                        
                        try context.delete(model: SessionSet.self)
                        try context.delete(model: SessionRep.self)

                        
                        try context.delete(model: SplitDay.self)
                        
                        try context.delete(model: Exercise.self)
                        try context.delete(model: Session.self)
                        try context.delete(model: SessionExercise.self)
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
            splitDays = try! context.fetch(FetchDescriptor<SplitDay>(sortBy: [SortDescriptor(\.timestamp)]))
            exercises = try! context.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.timestamp)]))
            ESD = try! context.fetch(FetchDescriptor<ExerciseSplitDay>(sortBy: [SortDescriptor(\.id)]))
            
            sessions = try! context.fetch(FetchDescriptor<Session>(sortBy: [SortDescriptor(\.timestamp)]))
            sessionSets = try! context.fetch(FetchDescriptor<SessionSet>(sortBy: [SortDescriptor(\.timestamp)]))
            sessionReps = try! context.fetch(FetchDescriptor<SessionRep>(sortBy: [SortDescriptor(\.id)]))
            
            sessionExercises = try! context.fetch(FetchDescriptor<SessionExercise>(sortBy: [SortDescriptor(\.id)]))
            
            users = try! context.fetch(FetchDescriptor<User>(sortBy: [SortDescriptor(\.lastLogin)]))

        }
    }
}
