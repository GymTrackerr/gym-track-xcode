//
//  GymTrackerWatchApp.swift
//  GymTrackerWatch Watch App
//
//  Created by Daniel Kravec on 2025-12-07.
//

import SwiftUI
#if os(watchOS)
import WatchConnectivity
#endif

@main
struct GymTrackerWatch_Watch_AppApp: App {
    @StateObject var timerModel = WatchTimerExtensionModel()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(timerModel)
        }
    }
}

struct RootView: View {
//    @State private var syncedUserName: String?
//    @State private var watchDelegate: WatchDelegate?
    
    var body: some View {
        Group {
            WatchContentView()
        }
    }
}
