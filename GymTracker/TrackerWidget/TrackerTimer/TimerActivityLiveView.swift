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

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let model = LiveActivityTimerModel(context: context, date: timeline.date)
            let snapshot = model.snapshot

            VStack(spacing: 8) {
                Text(model.title)
                    .font(.headline)

                if snapshot.isPaused {
                    Text(model.displayText)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                } else {
                    if let endDate = model.endDate {
                        Text(timerInterval: Date()...endDate, countsDown: true)
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                    } else {
                        Text(model.displayText)
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                    }
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
