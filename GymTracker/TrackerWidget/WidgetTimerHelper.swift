//
//  WidgetTimerHelper.swift
//  TrackerWidget
//
//  Created by Daniel Kravec on 2025-12-07.
//

import ActivityKit
import WidgetKit
import Foundation

struct WidgetTimerSnapshot {
    let remainingSeconds: Int
    let isPaused: Bool
    let lastUpdateTime: Date
    let baselineRemainingSeconds: Int

    var endDate: Date {
        lastUpdateTime.addingTimeInterval(TimeInterval(baselineRemainingSeconds))
    }
}

private struct SharedTimerState: Codable {
    let remainingSeconds: Int
    let totalLength: Int
    let isPaused: Bool
    let lastUpdateTime: TimeInterval
}

// Shared helper for live activity timer views
struct WidgetTimerHelper {
    let context: ActivityViewContext<TimerActivityAttributes>
    
    func snapshot(at date: Date = Date()) -> WidgetTimerSnapshot {
        let activitySnapshot = snapshotFromActivity(at: date)

        guard let sharedState = loadSharedTimerState() else {
            return activitySnapshot
        }

        let sharedDate = Date(timeIntervalSince1970: sharedState.lastUpdateTime)
        let sharedSnapshot = snapshotFromSharedState(sharedState, at: date)

        if sharedDate >= activitySnapshot.lastUpdateTime {
            return sharedSnapshot
        }
        return activitySnapshot
    }

    private func loadSharedTimerState() -> SharedTimerState? {
        guard
            let defaults = UserDefaults(suiteName: "group.net.novapro.GymTracker"),
            let data = defaults.data(forKey: "activeTimerState")
        else {
            return nil
        }

        return try? JSONDecoder().decode(SharedTimerState.self, from: data)
    }

    private func snapshotFromSharedState(_ state: SharedTimerState, at date: Date) -> WidgetTimerSnapshot {
        let lastUpdate = Date(timeIntervalSince1970: state.lastUpdateTime)
        let baseline = max(state.remainingSeconds, 0)

        if state.isPaused {
            return WidgetTimerSnapshot(
                remainingSeconds: baseline,
                isPaused: true,
                lastUpdateTime: lastUpdate,
                baselineRemainingSeconds: baseline
            )
        }

        let elapsedSinceUpdate = Int(date.timeIntervalSince(lastUpdate))
        return WidgetTimerSnapshot(
            remainingSeconds: max(baseline - elapsedSinceUpdate, 0),
            isPaused: false,
            lastUpdateTime: lastUpdate,
            baselineRemainingSeconds: baseline
        )
    }

    private func snapshotFromActivity(at date: Date) -> WidgetTimerSnapshot {
        let baseline = max(context.state.remainingSeconds, 0)
        if context.state.isPaused {
            let pausedRemaining = max(context.state.pausedAtSeconds, 0)
            return WidgetTimerSnapshot(
                remainingSeconds: pausedRemaining,
                isPaused: true,
                lastUpdateTime: context.state.lastUpdateTime,
                baselineRemainingSeconds: pausedRemaining
            )
        }

        let elapsedSinceUpdate = Int(date.timeIntervalSince(context.state.lastUpdateTime))
        return WidgetTimerSnapshot(
            remainingSeconds: max(baseline - elapsedSinceUpdate, 0),
            isPaused: false,
            lastUpdateTime: context.state.lastUpdateTime,
            baselineRemainingSeconds: baseline
        )
    }
}
