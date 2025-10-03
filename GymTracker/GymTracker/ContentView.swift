//
//  ContentView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftUI
import SwiftData

struct ContentView: View {
//    @EnvironmentObject var userService: UserService
    @State var query: String = ""
    @State var localSelected:Int = 0
    @State var showingOnboarding = false

    var body: some View {
        //        VStack {
        //            if (userService.accountCreated)
        TabView (selection: $localSelected) {
            Tab("Home", systemImage: "house", value: 0) {
                NavigationStack {
                    HomeView()
                }
            }
            Tab("Exercises", systemImage: "dumbbell", value: 1) {
                NavigationStack {
                    ExercisesView()
                }
            }
            
            
            Tab("Splits", systemImage: "figure.walk.motion", value: 2) {
                NavigationStack {
                    SplitDaysView()
                }
            }
            
            Tab("Search", systemImage: "magnifyingglass", value: 3, role: .search) {
                NavigationStack {
                    SearchView(query: $query)
                        .searchable(text: $query)

                }
            }
        }
//        .searchable(text: $query)
        .tabBarMinimizeBehavior(TabBarMinimizeBehavior.onScrollDown)
        .tabBarMinimizeBehavior(TabBarMinimizeBehavior.onScrollUp)
        //        }
    }
}

struct OnBoardView: View {
    @EnvironmentObject var userService: UserService
    @State var userName : String = ""

    var body: some View {
        VStack {
            Text("Welcome to GymTracker")
                .font(Font.largeTitle)
                .foregroundColor(.primary)
                .padding()
            Text("Please enter your name to get started")
                .font(.title)
                .foregroundColor(.secondary)
                .padding()
            
            TextField("Name", text: $userName)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            // make a user
            Button {
                userService.addUser(text: userName)
                userName = ""
            } label: {
                Label("Submit", systemImage: "plus.circle")
                    .font(.title2)
                    .padding()
            }
            .disabled(userName.trimmingCharacters(in: .whitespaces).isEmpty)
            Spacer()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
