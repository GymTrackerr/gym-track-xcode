//
//  SharedTimerController.swift
//  GymTracker
//
//  Created by OpenAI Codex on 2026-04-14.
//

import Foundation

enum SharedTimerController {
    static func timeString(_ seconds: Int) -> String {
        let clampedSeconds = max(seconds, 0)
        let minutes = clampedSeconds / 60
        let remainder = clampedSeconds % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }

    static func snapshot(
        from sharedState: SharedTimerState?,
        expectedTimerId: String? = nil,
        at date: Date = Date()
    ) -> SharedTimerRuntimeSnapshot {
        guard let sharedState else {
            return emptySnapshot()
        }

        let normalizedTimerId = normalizeTimerId(sharedState.timerId)
        if let expectedTimerId,
           expectedTimerId.isEmpty == false,
           normalizedTimerId != expectedTimerId.lowercased() {
            return emptySnapshot()
        }

        let lastUpdateTime = Date(timeIntervalSince1970: sharedState.lastUpdateTime)
        let remainingSeconds: Int

        if sharedState.isPaused {
            remainingSeconds = max(sharedState.remainingSeconds, 0)
        } else {
            let elapsedSinceUpdate = Int(date.timeIntervalSince(lastUpdateTime))
            remainingSeconds = max(sharedState.remainingSeconds - elapsedSinceUpdate, 0)
        }

        return SharedTimerRuntimeSnapshot(
            timerId: normalizedTimerId,
            displayedSeconds: max(sharedState.totalLength - remainingSeconds, 0),
            remainingSeconds: remainingSeconds,
            totalLength: max(sharedState.totalLength, 0),
            isPaused: sharedState.isPaused,
            hasTimer: true,
            lastUpdateTime: lastUpdateTime
        )
    }

    static func snapshot(
        from watchTimer: WatchTimerSnapshot?,
        pendingLength: Int,
        at date: Date = Date()
    ) -> SharedTimerRuntimeSnapshot {
        guard let watchTimer else {
            return SharedTimerRuntimeSnapshot(
                timerId: nil,
                displayedSeconds: max(pendingLength, 0),
                remainingSeconds: nil,
                totalLength: max(pendingLength, 0),
                isPaused: false,
                hasTimer: false,
                lastUpdateTime: .distantPast
            )
        }

        let displayedSeconds: Int
        if watchTimer.isPaused {
            displayedSeconds = max(watchTimer.elapsedTime, 0)
        } else if let startTime = watchTimer.startTime {
            displayedSeconds = max(
                watchTimer.elapsedTime + Int(date.timeIntervalSince(startTime)),
                0
            )
        } else {
            displayedSeconds = max(watchTimer.elapsedTime, 0)
        }

        let remainingSeconds: Int?
        if watchTimer.timerLength > 0 {
            remainingSeconds = max(watchTimer.timerLength - displayedSeconds, 0)
        } else {
            remainingSeconds = nil
        }

        return SharedTimerRuntimeSnapshot(
            timerId: watchTimer.id.lowercased(),
            displayedSeconds: displayedSeconds,
            remainingSeconds: remainingSeconds,
            totalLength: max(watchTimer.timerLength, 0),
            isPaused: watchTimer.isPaused,
            hasTimer: true,
            lastUpdateTime: watchTimer.updatedAt
        )
    }

    static func mergedActivitySnapshot(
        sharedState: SharedTimerState?,
        activityRemainingSeconds: Int,
        activityTimerId: String,
        isPaused: Bool,
        pausedAtSeconds: Int,
        lastUpdateTime: Date,
        totalLength: Int,
        at date: Date = Date()
    ) -> SharedTimerRuntimeSnapshot {
        let activitySnapshot = activitySnapshot(
            remainingSeconds: activityRemainingSeconds,
            timerId: activityTimerId,
            isPaused: isPaused,
            pausedAtSeconds: pausedAtSeconds,
            lastUpdateTime: lastUpdateTime,
            totalLength: totalLength,
            at: date
        )

        let normalizedActivityTimerId = normalizeTimerId(activityTimerId)
        let sharedSnapshot = snapshot(
            from: sharedState,
            expectedTimerId: normalizedActivityTimerId,
            at: date
        )
        guard sharedSnapshot.hasTimer else {
            return activitySnapshot
        }

        return sharedSnapshot.lastUpdateTime >= activitySnapshot.lastUpdateTime
            ? sharedSnapshot
            : activitySnapshot
    }

    private static func activitySnapshot(
        remainingSeconds: Int,
        timerId: String,
        isPaused: Bool,
        pausedAtSeconds: Int,
        lastUpdateTime: Date,
        totalLength: Int,
        at date: Date
    ) -> SharedTimerRuntimeSnapshot {
        let baselineRemaining = max(remainingSeconds, 0)
        let resolvedRemaining: Int

        if isPaused {
            resolvedRemaining = max(pausedAtSeconds, 0)
        } else {
            let elapsedSinceUpdate = Int(date.timeIntervalSince(lastUpdateTime))
            resolvedRemaining = max(baselineRemaining - elapsedSinceUpdate, 0)
        }

        return SharedTimerRuntimeSnapshot(
            timerId: normalizeTimerId(timerId),
            displayedSeconds: max(totalLength - resolvedRemaining, 0),
            remainingSeconds: resolvedRemaining,
            totalLength: max(totalLength, 0),
            isPaused: isPaused,
            hasTimer: true,
            lastUpdateTime: lastUpdateTime
        )
    }

    private static func emptySnapshot() -> SharedTimerRuntimeSnapshot {
        SharedTimerRuntimeSnapshot(
            timerId: nil,
            displayedSeconds: 0,
            remainingSeconds: nil,
            totalLength: 0,
            isPaused: false,
            hasTimer: false,
            lastUpdateTime: .distantPast
        )
    }

    private static func normalizeTimerId(_ timerId: String) -> String? {
        let trimmed = timerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        return trimmed.lowercased()
    }
}
