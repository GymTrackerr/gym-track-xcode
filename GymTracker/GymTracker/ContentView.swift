//
//  ContentView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var timerService: TimerService
    
    @State var query: String = ""
    @State var localSelected:Int = 0
    @State var showingOnboarding = false
    
    @State var linkActive = false
    @State var selectedLink = -1

    var body: some View {
        TabView (selection: $localSelected) {
            Tab("Home", systemImage: "house", value: 0) {
                NavigationStack {
                    GlassEffectContainer {
                        HomeView()
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.85, green: 0.1, blue: 0.1),//.red,
                                        Color.clear//gray.opacity(0.3)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: 400)
                                .frame(maxHeight: .infinity, alignment: .top)
                                .ignoresSafeArea(edges: .top)
                            )
                            .navigationDestination(isPresented: $linkActive) {
                                TimerView()
                                    .background(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color(red: 0.85, green: 0.1, blue: 0.1),//.red,
                                                Color.clear//gray.opacity(0.3)
                                            ]),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                        .frame(height: 400)
                                        .frame(maxHeight: .infinity, alignment: .top)
                                        .ignoresSafeArea(edges: .top)
                                    )
                            }
                    }
                }
            }
            Tab("Exercises", systemImage: "dumbbell", value: 1) {
                NavigationStack {
                    ExercisesView()
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.85, green: 0.1, blue: 0.1),//.red,
                                    Color.clear//gray.opacity(0.3)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 400)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .ignoresSafeArea(edges: .top)
                        )
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
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            timerService.appDidEnterBackground()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            timerService.appDidBecomeActive()
        }

        //.searchable(text: $query)
        .tabBarMinimizeIfAvailable()
        //        }
        .onOpenURL { url in
            print("Received deep link: \(url)")
            linkActive = true
        }
        // 4.

    }
}
extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, content: (Self) -> Content) -> some View {
        if condition {
            content(self)
        } else {
            self
        }
    }
}

extension View {
    @ViewBuilder func tabBarMinimizeIfAvailable() -> some View {
        if #available(iOS 26, *) {
            self
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabBarMinimizeBehavior(.onScrollUp)
        } else {
            self
        }
    }
}


struct OnBoardView: View {
    @EnvironmentObject var userService: UserService
    
    var body: some View {
        VStack {
            switch userService.onBoardingScreen {
            case 0:
                OnBoardScreen0()
            case 1:
                OnBoardScreen1()
            default:
                EmptyView()
            }
        }
    }
}

struct OnBoardScreen0: View {
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
            
            Button {
                userService.addUser(text: userName)
                userName = ""
                userService.onBoardingScreen = 1
            } label: {
                Label("Submit", systemImage: "plus.circle")
                    .font(.title2)
                    .padding()
            }
            .disabled(userName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

struct OnBoardScreen1: View {
    @EnvironmentObject var userService: UserService

    var body: some View {
        VStack {
            Text("Welcome, \(userService.currentUser?.name ?? "")")
                .font(Font.largeTitle)
                .foregroundColor(.primary)
                .padding()
            Button {
                userService.onBoardingScreen = 2
                userService.onBoarding = false
            } label: {
                Label("Proceed", systemImage: "plus.circle")
                    .font(.title2)
                    .padding()
            }
        }
    }
}
