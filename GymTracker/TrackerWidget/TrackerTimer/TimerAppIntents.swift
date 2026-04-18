//
//  TimerAppIntents.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-12-07.
//

import AppIntents
import ActivityKit
import WidgetKit
import Foundation

@MainActor
private enum TimerActivitySync {
    private static let appGroupIdentifier = "group.net.novapro.GymTracker"
    private static let pendingCommandKey = "pendingTimerControlCommand"

    private struct RuntimeState {
        var remainingSeconds: Int
        var totalLength: Int
        var isPaused: Bool
        var timerId: String
    }

    private struct PendingTimerControlCommand: Codable {
        let action: String
        let remainingSeconds: Int?
        let requestedAt: TimeInterval
        let timerId: String
    }

    private static func defaults() -> UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    private static func currentState(at now: Date = Date()) -> RuntimeState? {
        guard let activity = Activity<TimerActivityAttributes>.activities.first else {
            return nil
        }

        let state = activity.content.state
        let remaining: Int
        if state.isPaused {
            remaining = max(state.pausedAtSeconds, 0)
        } else {
            let elapsed = Int(now.timeIntervalSince(state.lastUpdateTime))
            remaining = max(state.remainingSeconds - elapsed, 0)
        }

        return RuntimeState(
            remainingSeconds: remaining,
            totalLength: max(activity.attributes.totalLength, 0),
            isPaused: state.isPaused,
            timerId: state.timerId
        )
    }

    private static func savePendingCommand(action: String, remainingSeconds: Int?, timerId: String) {
        let command = PendingTimerControlCommand(
            action: action,
            remainingSeconds: remainingSeconds,
            requestedAt: Date().timeIntervalSince1970,
            timerId: timerId
        )
        guard let data = try? JSONEncoder().encode(command) else { return }
        defaults()?.set(data, forKey: pendingCommandKey)
    }

    private static func updateActivities(from state: RuntimeState) async {
        let now = Date()
        for activity in Activity<TimerActivityAttributes>.activities {
            let content = ActivityContent(
                state: TimerActivityAttributes.ContentState(
                    remainingSeconds: state.remainingSeconds,
                    isPaused: state.isPaused,
                    pausedAtSeconds: state.isPaused ? state.remainingSeconds : 0,
                    lastUpdateTime: now,
                    timerId: state.timerId.isEmpty ? activity.content.state.timerId : state.timerId
                ),
                staleDate: now.addingTimeInterval(24 * 3600)
            )
            await activity.update(content)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func pause() async {
        guard var state = currentState() else { return }
        guard !state.isPaused else { return }

        state.isPaused = true
        savePendingCommand(action: "pause", remainingSeconds: state.remainingSeconds, timerId: state.timerId)
        await updateActivities(from: state)
    }

    static func resume() async {
        guard var state = currentState() else { return }
        guard state.isPaused else { return }

        state.isPaused = false
        savePendingCommand(action: "resume", remainingSeconds: state.remainingSeconds, timerId: state.timerId)
        await updateActivities(from: state)
    }

    static func cancel() async {
        let timerId = currentState()?.timerId ?? ""
        savePendingCommand(action: "cancel", remainingSeconds: nil, timerId: timerId)

        for activity in Activity<TimerActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct PauseTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause Timer"

    @MainActor
    func perform() async throws -> some IntentResult {
        await TimerActivitySync.pause()
        return .result()
    }
}

struct ResumeTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume Timer"

    @MainActor
    func perform() async throws -> some IntentResult {
        await TimerActivitySync.resume()
        return .result()
    }
}

struct CancelTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Cancel Timer"

    @MainActor
    func perform() async throws -> some IntentResult {
        await TimerActivitySync.cancel()
        return .result()
    }
}
