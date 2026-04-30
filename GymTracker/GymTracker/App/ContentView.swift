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
    
    @State var query: String = ""
    @State var localSelected:Int = 0
    
    @State var linkActive = false
    @State var selectedLink = -1
#if DEBUG
    @State private var showingDebugNotesImport = false
#endif

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
            
            if userService.currentUser?.showNutritionTab ?? true {
                Tab("Nutrition", systemImage: "fork.knife", value: 3) {
                    NavigationStack {
                        NutritionDayView().appBackground()
                    }
                }
            }
            
            Tab("Sessions", systemImage: "list.bullet.rectangle", value: 2) {
                NavigationStack {
                    SessionsPageView()
                        .appBackground()
                }
            }
            
            Tab("Exercises", systemImage: "dumbbell", value: 1) {
                NavigationStack {
                    ExercisesView()
                        .appBackground()
                }
            }

            Tab("Programme", systemImage: "figure.walk.motion", value: 4) {
                NavigationStack {
                    ProgramsRootView()
                        .appBackground()
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
        .onChange(of: userService.currentUser?.showNutritionTab ?? true) {
            if !(userService.currentUser?.showNutritionTab ?? true), localSelected == 3 {
                localSelected = 0
            }
        }

        //.searchable(text: $query)
        .tabBarMinimizeIfAvailable()
        //        }
        .onOpenURL { url in
            print("Received deep link: \(url)")
            linkActive = true
        }
        .onAppear {
#if DEBUG
            Task.detached(priority: .background) {
                DebugHarness.runAll()
            }
#endif
        }
#if false
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button {
                    showingDebugNotesImport = true
                } label: {
                    Label("Debug Notes Import", systemImage: "doc.text")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showingDebugNotesImport) {
            NotesImportView(currentUserId: userService.currentUser?.id)
        }
#endif
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
