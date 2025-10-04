//
//  SettingsView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-04.
//
import SwiftUI

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
