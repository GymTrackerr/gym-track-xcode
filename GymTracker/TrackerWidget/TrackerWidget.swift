//
//  TrackerWidget.swift
//  TrackerWidget
//
//  Created by Daniel Kravec on 2025-12-07.
//

import WidgetKit
import SwiftUI
import Combine

// Home Screen Widget Entry
struct HomeScreenEntry: TimelineEntry {
    let date: Date
}

// Home Screen Widget Provider
struct HomeScreenProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeScreenEntry {
        HomeScreenEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (HomeScreenEntry) -> Void) {
        let entry = HomeScreenEntry(date: Date())
        completion(entry)
    }
    
   func getTimeline(in context: Context, completion: @escaping (Timeline<HomeScreenEntry>) -> Void) {
        let entry = HomeScreenEntry(date: Date())
        let nextRefresh = Calendar.current.date(byAdding: .second, value: 30, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

// Home Screen Widget Entry View
struct HomeScreenEntryView: View {
    var entry: HomeScreenEntry
    // @State private var updateTrigger = UUID()
    // @State private var lastDisplayedSeconds = -1
    
    var timerData: (remaining: Int, total: Int, isPaused: Bool, hasTimer: Bool) {
        // Read from the shared UserDefaults with App Groups
        let defaults = UserDefaults(suiteName: "group.net.novapro.GymTracker")
        
        if let timerData = defaults?.data(forKey: "activeTimerState"),
           let json = try? JSONSerialization.jsonObject(with: timerData) as? [String: Any],
           let remainingSeconds = json["remainingSeconds"] as? Int,
           let totalLength = json["totalLength"] as? Int,
           let isPaused = json["isPaused"] as? Bool,
           let lastUpdateTimeInterval = json["lastUpdateTime"] as? TimeInterval {
            
            let lastUpdateTime = Date(timeIntervalSince1970: lastUpdateTimeInterval)
            let elapsedSinceUpdate = Int(Date().timeIntervalSince(lastUpdateTime))
            let currentRemaining = max(remainingSeconds - elapsedSinceUpdate, 0)
            
            return (remaining: currentRemaining, total: totalLength, isPaused: isPaused, hasTimer: true)
        }
        
        return (remaining: 0, total: 90, isPaused: false, hasTimer: false)
    }
    
    var progress: CGFloat {
        guard timerData.total > 0 else { return 0 }
        return CGFloat(timerData.remaining) / CGFloat(timerData.total)
    }
    
    var ringColor: Color {
        let percent = progress
        if percent > 0.5 { return .green }
        if percent > 0.25 { return .yellow }
        return .red
    }

    var body: some View {
        VStack(spacing: 10) {
            if timerData.hasTimer && timerData.remaining > 0 {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 6)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 4) {
                        Text(timeString(timerData.remaining))
                            .font(.system(size: 28, weight: .bold, design: .rounded))

                        if timerData.isPaused {
                            Text("PAUSED")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                }
                .frame(width: 100, height: 100)
                
                Text("Rest Timer")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 40))
                    
                    Text("No Timer")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Start a timer in the app")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "gymtracker//TrackerTimer"))
    }

    private func timeString(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// Home Screen Widget
struct HomeScreenWidget: Widget {
    let kind: String = "HomeScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HomeScreenProvider()) { entry in
            HomeScreenEntryView(entry: entry)
        }
        .supportedFamilies([.systemSmall, .systemMedium])
        .configurationDisplayName("Gym Timer")
        .description("Shows your current rest timer")
    }
}

#Preview(as: .systemSmall) {
    HomeScreenWidget()
} timeline: {
    HomeScreenEntry(date: Date())
}

