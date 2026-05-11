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
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var nutritionService: NutritionService
    @EnvironmentObject var healthKitDailyStore: HealthKitDailyStore
    
    @State var localSelected:Int = 0
    
    @State var linkActive = false
    @State private var nutritionLogRequestID: UUID?

    var body: some View {
        TabView (selection: $localSelected) {
            Tab("Home", systemImage: "house", value: 0) {
                NavigationStack {
                    GlassEffectContainer {
                        HomeView()
                            .appBackground()
                            .navigationDestination(isPresented: $linkActive) {
                                TimerView()
                            }
                    }
                }
            }
            
            if userService.currentUser?.showNutritionTab ?? true {
                Tab("Nutrition", systemImage: "fork.knife", value: 3) {
                    NavigationStack {
                        NutritionDayView(openLogRequestID: nutritionLogRequestID)
                    }
                }
            }
            
            Tab("Sessions", systemImage: "list.bullet.rectangle", value: 2) {
                NavigationStack {
                    SessionsPageView()
                }
            }
            
            Tab("Exercises", systemImage: "dumbbell", value: 1) {
                NavigationStack {
                    ExercisesView()
                }
            }

            Tab("Programme", systemImage: "figure.walk.motion", value: 4) {
                NavigationStack {
                    ProgramsRootView()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            timerService.appDidEnterBackground()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            timerService.appDidBecomeActive()
            nutritionService.refreshWidgetSnapshot()
        }
        .onChange(of: userService.currentUser?.showNutritionTab ?? true) {
            if !(userService.currentUser?.showNutritionTab ?? true), localSelected == 3 {
                localSelected = 0
            }
        }
        .onChange(of: healthKitDailyStore.refreshToken) {
            nutritionService.refreshWidgetSnapshot()
        }
        .tabBarMinimizeIfAvailable()
        .onOpenURL { url in
            print("Received deep link: \(url)")
            handleDeepLink(url)
        }
        .onAppear {
#if DEBUG
            Task.detached(priority: .background) {
                DebugHarness.runAll()
            }
#endif
        }
    }

    private func handleDeepLink(_ url: URL) {
        let host = url.host ?? ""
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let destination = ([host, path].filter { !$0.isEmpty }.joined(separator: "/"))
            .lowercased()

        switch destination {
        case "nutrition":
            if userService.currentUser?.showNutritionTab ?? true {
                linkActive = false
                localSelected = 3
            }
        case "nutrition/log":
            if userService.currentUser?.showNutritionTab ?? true {
                linkActive = false
                localSelected = 3
                nutritionLogRequestID = UUID()
            }
        case "trackertimer", "timer":
            localSelected = 0
            linkActive = true
        default:
            localSelected = 0
            linkActive = true
        }
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
