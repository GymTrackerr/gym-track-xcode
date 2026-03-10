//
//  LockScreenLiveActivityView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-12-07.
//

import SwiftUI
import ActivityKit
import WidgetKit
import AppIntents

struct LockScreenLiveActivityView: View {
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
            let progress = progressValue(remainingSeconds: remainingSeconds)

            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.25), lineWidth: 6)

                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(ringColor(remainingSeconds: remainingSeconds), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))

                        if remainingSeconds > 0 {
                            countdownText(snapshot: snapshot)
                        } else {
                            Text("DONE")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.red)
                        }
                    }
                    .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.attributes.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(remainingSeconds > 0 ? (snapshot.isPaused ? "Paused" : "Running") : "Completed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                if remainingSeconds > 0 {
                    HStack(spacing: 10) {
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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func countdownText(snapshot: WidgetTimerSnapshot) -> some View {
        if snapshot.isPaused {
            Text(timeString(snapshot.remainingSeconds))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
        } else {
            Text(timerInterval: Date()...snapshot.endDate, countsDown: true)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
    }

    private func progressValue(remainingSeconds: Int) -> CGFloat {
        guard context.attributes.totalLength > 0 else { return 1 }
        return CGFloat(remainingSeconds) / CGFloat(context.attributes.totalLength)
    }

    private func ringColor(remainingSeconds: Int) -> Color {
        remainingSeconds <= 10 ? .red : .green
    }
}
