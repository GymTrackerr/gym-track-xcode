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
    
    private let helper: WidgetTimerHelper
    
    init(context: ActivityViewContext<TimerActivityAttributes>) {
        self.context = context
        self.helper = WidgetTimerHelper(context: context)
    }
    
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let snapshot = helper.snapshot(at: timeline.date)
            let remainingSeconds = snapshot.remainingSeconds

            VStack(spacing: 10) {
                if remainingSeconds > 0 {
                    countdownText(snapshot: snapshot)
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
    private func countdownText(snapshot: WidgetTimerSnapshot) -> some View {
        if snapshot.isPaused {
            Text(timeString(snapshot.remainingSeconds))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
        } else {
            Text(timerInterval: Date()...snapshot.endDate, countsDown: true)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
    }
}
