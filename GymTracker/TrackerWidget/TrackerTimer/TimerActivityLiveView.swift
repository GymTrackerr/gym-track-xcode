//
//  TimerActivityLiveView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-12-07.

import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

struct TimerActivityLiveView: View {
    let context: ActivityViewContext<TimerActivityAttributes>
    
    private let helper: WidgetTimerHelper
    
    init(context: ActivityViewContext<TimerActivityAttributes>) {
        self.context = context
        self.helper = WidgetTimerHelper(context: context)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let snapshot = helper.snapshot(at: timeline.date)
            let remainingSeconds = snapshot.remainingSeconds

            VStack(spacing: 8) {
                Text(context.attributes.title)
                    .font(.headline)

                if snapshot.isPaused {
                    Text(timeString(remainingSeconds))
                        .font(.system(size: 42, weight: .bold, design: .rounded))
//                        .monospacedDigit()
                } else {
                    Text(timerInterval: Date()...snapshot.endDate, countsDown: true)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
//                        .monospacedDigit()
                }

                HStack {
                    if snapshot.isPaused {
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
        }
    }
}
