//
//  ExtensionTimerService.swift
//  GymTracker
//
//  Created by OpenAI Codex on 2026-04-14.
//

import Foundation
#if canImport(ActivityKit)
import ActivityKit
import WidgetKit
#endif

struct ExtensionTimerService {
    func widgetSnapshot(
        forTimerId timerId: String? = nil,
        at date: Date = Date()
    ) -> SharedTimerRuntimeSnapshot {
        SharedTimerStateStore.snapshot(
            at: date,
            expectedTimerId: timerId
        )
    }

    func watchSnapshot(
        timer: WatchTimerSnapshot?,
        pendingLength: Int,
        at date: Date = Date()
    ) -> SharedTimerRuntimeSnapshot {
        SharedTimerController.snapshot(
            from: timer,
            pendingLength: pendingLength,
            at: date
        )
    }

    func displayText(for snapshot: SharedTimerRuntimeSnapshot) -> String {
        SharedTimerController.timeString(snapshot.primarySeconds)
    }

#if canImport(ActivityKit)
    func liveActivitySnapshot(
        context: ActivityViewContext<TimerActivityAttributes>,
        at date: Date = Date()
    ) -> SharedTimerRuntimeSnapshot {
        SharedTimerController.mergedActivitySnapshot(
            sharedState: SharedTimerStateStore.loadState(),
            activityRemainingSeconds: context.state.remainingSeconds,
            activityTimerId: context.state.timerId,
            isPaused: context.state.isPaused,
            pausedAtSeconds: context.state.pausedAtSeconds,
            lastUpdateTime: context.state.lastUpdateTime,
            totalLength: context.attributes.totalLength,
            at: date
        )
    }
#endif
}
