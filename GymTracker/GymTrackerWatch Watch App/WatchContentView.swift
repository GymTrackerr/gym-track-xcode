//
//  WatchContentView.swift
//  GymTrackerWatch Watch App
//
//  Created by Daniel Kravec on 2025-12-07.
//

import SwiftUI
import SwiftData

struct WatchContentView: View {
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var timerService: TimerService
//    @EnvironmentObject var sessionService: SessionService
    
    var body: some View {
        TabView {
//            HomeView()
            // Timer Tab
            WatchTimerView()

            // Sessions Tab
//            WatchSessionsView()
            
            // Settings Tab
//            WatchSettingsView()
        }
        .tabViewStyle(.page)
    }
}
