//
//  IslandExpandedView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-12-07.
//

import SwiftUI
import ActivityKit
import WidgetKit
import Combine
import AppIntents

struct IslandExpandedView: View {
    let context: ActivityViewContext<TimerActivityAttributes>
    @State private var updateTrigger = UUID()
    @State private var lastDisplayedSeconds = -1
    
    private let helper: WidgetTimerHelper
    
    init(context: ActivityViewContext<TimerActivityAttributes>) {
        self.context = context
        self.helper = WidgetTimerHelper(context: context)
    }
    
    private var timer: Timer.TimerPublisher {
        helper.getTimer(isPaused: context.state.isPaused)
    }
    
    var remainingSeconds: Int {
        helper.remainingSeconds
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Text(remainingSeconds > 0 ?
                 timeString(remainingSeconds) : "DONE")
            .font(.system(size: 32, weight: .bold, design: .rounded))
            .foregroundColor(context.state.isPaused ? .orange : remainingSeconds <= 10 ? .red : .primary)
            
            HStack(spacing: 20) {
                if remainingSeconds > 0 {
                    if context.state.isPaused {
                        Button(intent: ResumeTimerIntent()) {
                            Text("Resume")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button(intent: PauseTimerIntent()) {
                            Text("Pause")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    Button(intent: CancelTimerIntent()) {
                        Text("Cancel")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
        }
        .padding()
        .id(updateTrigger)
        .onReceive(timer.autoconnect()) { _ in
            // Only update if seconds actually changed
            if remainingSeconds != lastDisplayedSeconds {
                lastDisplayedSeconds = remainingSeconds
                updateTrigger = UUID()
            }
        }
        .onAppear {
            lastDisplayedSeconds = remainingSeconds
        }
    }
}
