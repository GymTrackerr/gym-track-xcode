//
//  TimerLiveActivityManager.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-12-07.
//

import ActivityKit
import Foundation
import Combine
import WidgetKit
import SwiftData

@MainActor
final class LiveActivityManager: ObservableObject {
    @Published var activity: Activity<TimerActivityAttributes>?

    static let shared = LiveActivityManager()
    private var startDate: Date = Date()
    private var timerId: String = ""
    
    private init() {}
    
    // Helper Methods
    private func saveTimerStateToWidget(remainingSeconds: Int, totalLength: Int, isPaused: Bool) {
        let timerState: [String: Any] = [
            "remainingSeconds": max(remainingSeconds, 0),
            "totalLength": totalLength,
            "isPaused": isPaused,
            "lastUpdateTime": Date().timeIntervalSince1970
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: timerState) {
            let defaults = UserDefaults(suiteName: "group.net.novapro.GymTracker")
            defaults?.set(jsonData, forKey: "activeTimerState")
        }
    }
    
    private func clearTimerStateFromWidget() {
        let defaults = UserDefaults(suiteName: "group.net.novapro.GymTracker")
        defaults?.removeObject(forKey: "activeTimerState")
    }
    
    private var lastWidgetUpdate = Date.distantPast

    private func requestWidgetUpdate() {
        let now = Date()
        if now.timeIntervalSince(lastWidgetUpdate) > 1 { // 1 per second max
            lastWidgetUpdate = now
            WidgetCenter.shared.reloadTimelines(ofKind: "HomeScreenWidget")
        }
    }
    
    func start(length: Int, timerId: String = "") {
        if activity != nil {
            end()
        }

        let authInfo = ActivityAuthorizationInfo()
        
        guard authInfo.areActivitiesEnabled else {
            print("Live activities are not enabled")
            return
        }

        let attributes = TimerActivityAttributes(title: "Workout Timer", totalLength: length)
        startDate = Date()
        self.timerId = timerId

        // Set stale date far in the future so the activity stays visible
        // The app's ticker will keep updating it every second
        let staleDate = Date().addingTimeInterval(24 * 3600) // 24 hours

        let content = ActivityContent(
            state: TimerActivityAttributes.ContentState(
                remainingSeconds: length,
                isPaused: false,
                pausedAtSeconds: 0,
                lastUpdateTime: startDate,
                timerId: timerId
            ),
            staleDate: staleDate
        )

        do {
            activity = try Activity.request(attributes: attributes, content: content)
            // print("Live Activity started successfully with ID: \(timerId)")
        } catch {
            print("Live Activity start failed:", error)
        }
    }

    
    func update(remainingSeconds: Int, totalLength: Int, isPaused: Bool) {
        guard let act = activity else { return }
        
        // print("Updating live activity - remaining: \(remainingSeconds)s, total: \(totalLength)s, paused: \(isPaused)")
        
        // Always set stale date far in the future to keep activity visible
        // The app's ticker (running every 1 second) will keep updating it
        let staleDate = Date().addingTimeInterval(24 * 3600) // 24 hours in the future
        
        // Store a fresh "now" timestamp so views can calculate elapsed time from this point
        let now = Date()
        
        let content = ActivityContent(
            state: TimerActivityAttributes.ContentState(
                remainingSeconds: max(remainingSeconds, 0),
                isPaused: isPaused,
                pausedAtSeconds: isPaused ? max(remainingSeconds, 0) : 0,
                lastUpdateTime: now,
                timerId: timerId
            ),
            staleDate: staleDate
        )
        
        // Save state and update widget
        saveTimerStateToWidget(remainingSeconds: remainingSeconds, totalLength: totalLength, isPaused: isPaused)
        requestWidgetUpdate()
        
        Task { await act.update(content) }
    }
    
    func end(after seconds: UInt64 = 0) {
        guard let act = activity else {
            // print("Cannot end activity - no activity exists")
            return
        }
        
        // print("Ending live activity after \(seconds) seconds")
        
        Task {
            if seconds > 0 {
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            }
            
            let finalContent = ActivityContent(
                state: TimerActivityAttributes.ContentState(
                    remainingSeconds: 0,
                    isPaused: true,
                    pausedAtSeconds: 0,
                    lastUpdateTime: Date(),
                    timerId: timerId
                ),
                staleDate: nil
            )
            
            // Clear widget state and update
            clearTimerStateFromWidget()
            requestWidgetUpdate()
            
            await act.end(finalContent, dismissalPolicy: .immediate)
            self.activity = nil
        }
    }
}
