//
//  WatchContentView.swift
//  GymTrackerWatch Watch App
//
//  Created by Daniel Kravec on 2025-12-07.
//

import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject var timerModel: WatchTimerExtensionModel
    
    var body: some View {
        TabView {
            WatchHomeView()
        }
        .tabViewStyle(.page)
    }
}
