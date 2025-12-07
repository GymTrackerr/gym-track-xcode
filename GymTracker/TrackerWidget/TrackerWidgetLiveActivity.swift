//
//  TrackerWidgetLiveActivity.swift
//  TrackerWidget
//
//  Created by Daniel Kravec on 2025-12-07.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct TrackerWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct TrackerWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrackerWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension TrackerWidgetAttributes {
    fileprivate static var preview: TrackerWidgetAttributes {
        TrackerWidgetAttributes(name: "World")
    }
}

extension TrackerWidgetAttributes.ContentState {
    fileprivate static var smiley: TrackerWidgetAttributes.ContentState {
        TrackerWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: TrackerWidgetAttributes.ContentState {
         TrackerWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: TrackerWidgetAttributes.preview) {
   TrackerWidgetLiveActivity()
} contentStates: {
    TrackerWidgetAttributes.ContentState.smiley
    TrackerWidgetAttributes.ContentState.starEyes
}
