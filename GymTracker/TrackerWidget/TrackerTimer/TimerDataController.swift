//
//  TimerDataController.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-12-07.
//

import Foundation

struct TimerDataController {
    private static let timerService = ExtensionTimerService()

    struct TimerInfo {
        let elapsedTime: Int
        let isPaused: Bool
        let timerLength: Int
    }

    // The widget/activity extension only needs lightweight timer state from the app group.
    // It should not spin up the app's full persistence graph just to render timer UI.
    static func getTimerInfo(byId id: String) -> TimerInfo? {
        let snapshot = timerService.widgetSnapshot(forTimerId: id)
        guard snapshot.hasTimer else {
            return nil
        }

        return TimerInfo(
            elapsedTime: max(snapshot.displayedSeconds, 0),
            isPaused: snapshot.isPaused,
            timerLength: snapshot.totalLength
        )
    }
}
