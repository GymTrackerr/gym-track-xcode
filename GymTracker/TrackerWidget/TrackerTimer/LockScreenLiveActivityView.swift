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

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let model = LiveActivityTimerModel(context: context, date: timeline.date)
            let snapshot = model.snapshot
            let remainingSeconds = model.remainingSeconds
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
                            countdownText(model: model)
                        } else {
                            Text("DONE")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.red)
                        }
                    }
                    .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.title)
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
    private func countdownText(model: LiveActivityTimerModel) -> some View {
        let snapshot = model.snapshot
        if snapshot.isPaused {
            Text(model.displayText)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
        } else {
            if let endDate = model.endDate {
                Text(timerInterval: Date()...endDate, countsDown: true)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
            } else {
                Text(model.displayText)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
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
