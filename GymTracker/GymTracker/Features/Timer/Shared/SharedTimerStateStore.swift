//
//  SharedTimerStateStore.swift
//  GymTracker
//
//  Created by OpenAI Codex on 2026-04-14.
//

import Foundation

enum SharedTimerStateStore {
    private static let appGroupIdentifier = "group.net.novapro.GymTracker"
    private static let timerStateKey = "activeTimerState"

    static func loadState() -> SharedTimerState? {
        guard
            let defaults = UserDefaults(suiteName: appGroupIdentifier),
            let data = defaults.data(forKey: timerStateKey)
        else {
            return nil
        }

        return try? JSONDecoder().decode(SharedTimerState.self, from: data)
    }

    static func saveState(
        timerId: String,
        remainingSeconds: Int,
        totalLength: Int,
        isPaused: Bool,
        lastUpdateTime: Date = Date()
    ) {
        let state = SharedTimerState(
            timerId: timerId,
            remainingSeconds: max(remainingSeconds, 0),
            totalLength: max(totalLength, 0),
            isPaused: isPaused,
            lastUpdateTime: lastUpdateTime.timeIntervalSince1970
        )

        guard
            let defaults = UserDefaults(suiteName: appGroupIdentifier),
            let data = try? JSONEncoder().encode(state)
        else {
            return
        }

        defaults.set(data, forKey: timerStateKey)
    }

    static func clearState() {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        defaults?.removeObject(forKey: timerStateKey)
    }

    static func snapshot(
        at date: Date = Date(),
        expectedTimerId: String? = nil
    ) -> SharedTimerRuntimeSnapshot {
        SharedTimerController.snapshot(
            from: loadState(),
            expectedTimerId: expectedTimerId,
            at: date
        )
    }
}
