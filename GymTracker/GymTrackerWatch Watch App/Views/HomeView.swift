//
//  HomeView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-12-07.
//

import SwiftUI
import SwiftData

struct HomeView: View {
//    @EnvironmentObject var watchSession: WatchSessionManager
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var timerService: TimerService
    @EnvironmentObject var hkManager: HealthKitManager

    @State private var openedSession: Session? = nil
    @State private var navigateToSession:Bool = false
    
    var body: some View {
        VStack {
            if let _ = userService.currentUser {
                if !navigateToSession { // hide home content when navigating
                    ScrollView {
                        VStack {
                            HStack(spacing: 16) {
                                MetricCard(title: "Current Weight", value: String(hkManager.userWeight ?? 0.00), icon: "lock.fill")
                                
                                MetricCard(title: "Weekly Steps", value: String(hkManager.totalStepsWeek.rounded()), icon: "figure.walk.motion")
                            }
                            .padding(.horizontal)
                            
                            HStack(spacing: 16) {
                                
                                NavigationLink(destination:
                                    WatchTimerView()
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
                                ) {
                                    MetricCard(
                                        title: timerService.timer != nil ? "Timer" : "Start Timer",
                                        value: timerService.timer != nil ? timerService.formatted : "--:--",
                                        icon: "timer"
                                    )
                                }
                            }
                            .padding(.horizontal)

                            StepBarGraph()
                                .padding()
                                .glassEffect(in: .rect(cornerRadius: 16.0))
                                .padding(.horizontal)
                        
                            
                          
                           VStack {
//                               SessionsView(openedSession: $openedSession)
//                                   .onChange(of: openedSession) {
//                                       if openedSession != nil {
//                                           navigateToSession = true
//                                       }
//                                   }
                           }
                        }
                    }
                }
            } else {
                Text("Please continue to onboarding")
            }
        }
        .task {
            await hkManager.requestAuthorization()
            await hkManager.fetchWeeklySteps()
            await hkManager.fetchUserWeight()
        }
       .navigationDestination(isPresented: $navigateToSession) {
           Group {
               if let openedSession {
//                   SingleSessionView(session: openedSession)
               } else {
                   EmptyView()
               }
           }
       }
       .navigationTitle(userService.currentUser != nil ? "Welcome \(userService.currentUser!.name)" : "Home" )
       .toolbar {
//           ToolbarItem(placement: .navigationBarTrailing) {
//               NavigationLink(destination: SettingsView()) {
//                   Label("Settings", systemImage: "gearshape")
//               }
//           }
       }
    }
}
