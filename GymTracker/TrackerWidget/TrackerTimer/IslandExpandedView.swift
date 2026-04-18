//
//  IslandExpandedView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-12-07.
//

import SwiftUI
import ActivityKit
import WidgetKit
import AppIntents

struct IslandExpandedView: View {
    let context: ActivityViewContext<TimerActivityAttributes>
    
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let model = LiveActivityTimerModel(context: context, date: timeline.date)
            let snapshot = model.snapshot
            let remainingSeconds = model.remainingSeconds

            VStack(spacing: 10) {
                if remainingSeconds > 0 {
                    countdownText(model: model)
                        .foregroundColor(snapshot.isPaused ? .orange : (remainingSeconds <= 10 ? .red : .primary))
                } else {
                    Text("DONE")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.red)
                }

                HStack(spacing: 12) {
                    if remainingSeconds > 0 {
                        if snapshot.isPaused {
                            Button(intent: ResumeTimerIntent()) {
                                Text("Resume")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        } else {
                            Button(intent: PauseTimerIntent()) {
                                Text("Pause")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }

                        Button(intent: CancelTimerIntent()) {
                            Text("Cancel")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.red)
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
        }
    }

    @ViewBuilder
    private func countdownText(model: LiveActivityTimerModel) -> some View {
        let snapshot = model.snapshot
        if snapshot.isPaused {
            Text(model.displayText)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
        } else {
            if let endDate = model.endDate {
                Text(timerInterval: Date()...endDate, countsDown: true)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
            } else {
                Text(model.displayText)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
        }
    }
}
