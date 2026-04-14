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
        var entries: [HomeScreenEntry] = []
        let currentDate = Date()
        
        // Generate entries every 0.5 seconds for continuous updates
        for i in 0 ..< 120 {
            let entryDate = currentDate.addingTimeInterval(TimeInterval(Double(i) * 0.5))
            entries.append(HomeScreenEntry(date: entryDate))
        }
        
        // Refresh after 60 seconds (when timeline is exhausted)
        let nextRefresh = currentDate.addingTimeInterval(60)
        completion(Timeline(entries: entries, policy: .after(nextRefresh)))
    }
}

// Home Screen Widget Entry View
struct HomeScreenEntryView: View {
    var entry: HomeScreenEntry
    @State private var updateTrigger = UUID()
    
    var timerModel: HomeScreenTimerModel {
        HomeScreenTimerModel(date: entry.date)
    }
    
    var progress: CGFloat {
        timerModel.progress
    }

    var body: some View {
        VStack(spacing: 10) {
            if timerModel.hasVisibleTimer {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 6)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(timerModel.ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 4) {
                        Text(timerModel.displayText)
                            .font(.system(size: 28, weight: .bold, design: .rounded))

                        if timerModel.snapshot.isPaused {
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
        // Force re-renders every 0.5 seconds by updating state
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            updateTrigger = UUID()
        }
        .id(updateTrigger)
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
