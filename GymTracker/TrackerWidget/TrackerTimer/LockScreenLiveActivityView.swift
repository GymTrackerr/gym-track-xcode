//
//  LockScreenLiveActivityView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-12-07.
//

import SwiftUI
import ActivityKit
import WidgetKit
import Combine
import AppIntents

struct LockScreenLiveActivityView: View {
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
    
    var progress: CGFloat {
        guard context.attributes.totalLength > 0 else { return 1 }
        return CGFloat(remainingSeconds) /
        CGFloat(context.attributes.totalLength)
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 6)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                
                if remainingSeconds > 0 {
                    Text(timeString(remainingSeconds))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                } else {
                    Text("DONE")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.red)
                }
            }
            .frame(width: 80, height: 80)

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
            
            Text(context.attributes.title)
                .font(.headline)
                .foregroundColor(.secondary)
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
            print("LockScreenLiveActivityView appeared!")
            lastDisplayedSeconds = remainingSeconds
        }
    }

    var ringColor: Color {
        remainingSeconds <= 10 ? .red : .green
    }
}
