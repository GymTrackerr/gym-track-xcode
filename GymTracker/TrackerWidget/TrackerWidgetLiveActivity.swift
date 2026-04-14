//
//  TrackerWidgetLiveActivity.swift
//  TrackerWidget
//
//  Created by Daniel Kravec on 2025-12-07.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct TrackerWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            LockScreenLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    IslandExpandedView(context: context)
                }
            } compactLeading: {
                Text("⏱")
            } compactTrailing: {
                DynamicIslandCompactTimerView(context: context)
            } minimal: {
                Text("⏱")
            }
        }
    }
}
private struct DynamicIslandCompactTimerView: View {
    let context: ActivityViewContext<TimerActivityAttributes>

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let model = LiveActivityTimerModel(context: context, date: timeline.date)
            Group {
                if model.snapshot.isPaused {
                    Text(model.displayText)
                } else {
                    if let endDate = model.endDate {
                        Text(timerInterval: Date()...endDate, countsDown: true)
                    } else {
                        Text(model.displayText)
                    }
                }
            }
            .font(.caption2)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.trailing)
            .frame(width: 44, alignment: .trailing)
        }
        .frame(width: 44, alignment: .trailing)
    }
}
