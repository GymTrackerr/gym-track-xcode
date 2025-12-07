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
                Text(timeString(context.state.remainingSeconds))
            } minimal: {
                Text("⏱")
            }
        }
    }
}
