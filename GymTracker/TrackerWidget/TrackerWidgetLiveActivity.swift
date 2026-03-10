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
            let helper = WidgetTimerHelper(context: context)
            let snapshot = helper.snapshot(at: timeline.date)
            Group {
                if snapshot.isPaused {
                    Text(timeString(snapshot.remainingSeconds))
                } else {
                    Text(timerInterval: Date()...snapshot.endDate, countsDown: true)
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

