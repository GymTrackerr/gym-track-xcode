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
        SharedTimerStateStore.saveState(
            timerId: timerId,
            remainingSeconds: remainingSeconds,
            totalLength: totalLength,
            isPaused: isPaused
        )
    }
    
    private func clearTimerStateFromWidget() {
        SharedTimerStateStore.clearState()
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
        if activity != nil || !Activity<TimerActivityAttributes>.activities.isEmpty {
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

        // Running timers should expire close to completion if app is suspended.
        let staleDate = Date().addingTimeInterval(TimeInterval(max(length, 1) + 5))

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
        let clampedRemaining = max(remainingSeconds, 0)

        if clampedRemaining == 0 {
            // End from the live activity layer so dismissal still happens
            // even when the service-side completion path is delayed.
            end(after: 3)
            return
        }
        
        let staleDate: Date
        if isPaused {
            staleDate = Date().addingTimeInterval(24 * 3600)
        } else {
            staleDate = Date().addingTimeInterval(TimeInterval(clampedRemaining + 5))
        }
        
        // Store a fresh "now" timestamp so views can calculate elapsed time from this point
        let now = Date()
        
        let content = ActivityContent(
            state: TimerActivityAttributes.ContentState(
                remainingSeconds: clampedRemaining,
                isPaused: isPaused,
                pausedAtSeconds: isPaused ? clampedRemaining : 0,
                lastUpdateTime: now,
                timerId: timerId
            ),
            staleDate: staleDate
        )
        
        // Save state and update widget
        saveTimerStateToWidget(remainingSeconds: clampedRemaining, totalLength: totalLength, isPaused: isPaused)
        requestWidgetUpdate()
        
        Task { await act.update(content) }
    }
    
    func end(after seconds: UInt64 = 0) {
        // Clear shared snapshot immediately so widget views stop rendering stale state.
        clearTimerStateFromWidget()
        requestWidgetUpdate()

        Task {
            let endingTimerId = timerId
            let finalContent = ActivityContent(
                state: TimerActivityAttributes.ContentState(
                    remainingSeconds: 0,
                    isPaused: true,
                    pausedAtSeconds: 0,
                    lastUpdateTime: Date(),
                    timerId: endingTimerId
                ),
                staleDate: nil
            )

            let dismissalPolicy: ActivityUIDismissalPolicy
            if seconds > 0 {
                dismissalPolicy = .after(Date().addingTimeInterval(TimeInterval(seconds)))
            } else {
                dismissalPolicy = .immediate
            }

            if let act = activity {
                await act.end(finalContent, dismissalPolicy: dismissalPolicy)
            } else {
                for liveActivity in Activity<TimerActivityAttributes>.activities {
                    await liveActivity.end(finalContent, dismissalPolicy: dismissalPolicy)
                }
            }
            self.timerId = ""
            self.activity = nil
        }
    }
}
