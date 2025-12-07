//
//  TimerActivityLiveView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-12-07.

import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents
import Combine

struct TimerActivityLiveView: View {
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
        VStack(spacing: 8) {
            
            Text(context.attributes.title)
                .font(.headline)
            
            Text(timeString(remainingSeconds))
                .font(.system(size: 42, weight: .bold, design: .rounded))
            
            HStack {
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


