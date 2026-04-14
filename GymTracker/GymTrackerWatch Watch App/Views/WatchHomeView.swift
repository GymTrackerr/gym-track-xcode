//
//  WatchHomeView.swift
//  GymTrackerWatch Watch App
//
//  Created by OpenAI Codex on 2026-04-14.
//

import SwiftUI

struct WatchHomeView: View {
    @EnvironmentObject var timerModel: WatchTimerExtensionModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                WatchTimerView()

                Text(timerModel.isReachable ? "Connected to iPhone" : "Open the iPhone app to sync timer controls")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .navigationTitle("Timer")
    }
}
