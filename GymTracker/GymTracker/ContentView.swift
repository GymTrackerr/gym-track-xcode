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
                            .appBackground()
                            .navigationDestination(isPresented: $linkActive) {
                                TimerView()
                                    .appBackground()
                            }
                    }
                }
            }
            Tab("Exercises", systemImage: "dumbbell", value: 1) {
                NavigationStack {
                    ExercisesView()
                        .appBackground()
                }
            }
            
            
            Tab("Program", systemImage: "figure.walk.motion", value: 2) {
                NavigationStack {
                    SplitDaysView()
                }
            }
            /*
            if (localSelected == 1) {
                Tab("Search", systemImage: "magnifyingglass", value: 3, role: .search) {
                    NavigationStack {
                        SearchView(query: $query)
                            .searchable(text: $query)
                        
                    }
                }
            }
             */
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
                OnBoardScreenPermissions()
            case 2:
                OnBoardScreenFinal()
            default:
                EmptyView()
            }
            Spacer()
        }
        .appBackground()
    }
}

struct OnBoardScreen0: View {
    @EnvironmentObject var userService: UserService
    @State var userName : String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
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
            
//            Button {
//                userService.addUser(text: userName)
//                userName = ""
//                userService.onBoardingScreen = 1
//            } label: {
//                Label("Submit", systemImage: "plus.circle")
//                    .font(.title2)
//                    .padding()
//            }
            Spacer()

            Button("Next"){
                userService.addUser(text: userName)
                userName = ""
                userService.onBoardingScreen = 1
//            } label: {
//                Label("Next", systemImage: "plus.circle")
//                    .disabled(userName.trimmingCharacters(in: .whitespaces).isEmpty)

            }
            .disabled(userName.trimmingCharacters(in: .whitespaces).isEmpty)

            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
        .padding(24)
    }
}

struct OnBoardScreenPermissions: View {
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var hkManager: HealthKitManager

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Allow Health access to power GymTracker features like:")
                .font(.largeTitle)
                .bold()

            VStack(alignment: .leading, spacing: 20) {
                row("scalemass.fill", "Auto-fill your current weight (if available)")
                row("figure.walk", "Show weekly activity like steps and trends")
                row("heart.fill", "Keep your training data alongside your health history")
            }

            Button("Allow Health Access") {
                Task {
                    await hkManager.requestAuthorization()
                    
                    userService.hkUserAllow(connected: hkManager.hkConnected, requested: hkManager.hkRequested)
                }
            }
            .buttonStyle(.borderedProminent)

            Text("We only request the data needed for these features. You can change access anytime in the Health app or Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Next") {
                userService.onBoardingScreen = 2
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
        .padding(24)
    }

    private func row(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)

            Text(text)
                .font(.body)
        }
    }
}

struct OnBoardScreenFinal: View {
    @EnvironmentObject var userService: UserService

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Welcome, \(userService.currentUser?.name ?? "")")
                .font(Font.largeTitle)
                .foregroundColor(.primary)
                .padding()
            Text("You are ready to start using GymTracker")
            Spacer()

            
            Button("Done") {
                userService.onBoardingScreen = 3
                userService.onBoarding = false
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
        .padding(24)

//        .appBackground()
    }
}

struct AppBackground: View {
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.85, green: 0.1, blue: 0.1),//.red,
                Color.clear//gray.opacity(0.3)
            ]),
            startPoint: .top,
            endPoint: .bottom,
        )
        .frame(height: 400)
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
    }
}

extension View {
    func appBackground() -> some View {
        self.background(AppBackground())
    }
}
