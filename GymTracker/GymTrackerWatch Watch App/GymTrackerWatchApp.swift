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
    @StateObject var sessionManager = WatchSessionListener()

    var body: some Scene {
        WindowGroup {
            WatchTimerView()
                .environmentObject(sessionManager)
        }
    }
}

struct RootView: View {
//    @State private var syncedUserName: String?
//    @State private var watchDelegate: WatchDelegate?
    
    var body: some View {
        Group {
//            if let userName = syncedUserName {
                WatchTimerView()
//                Text("Welcome, \(userName)!")
//                    .font(.headline)
//                    .padding()
//            } else {
//                Text("Waiting for data from iPhone...")
//                    .multilineTextAlignment(.center)
//                    .font(.body)
//                    .padding()
////            }
        }
    }
}
