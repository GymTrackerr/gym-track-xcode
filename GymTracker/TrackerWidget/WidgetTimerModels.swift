//
//  WidgetTimerModels.swift
//  TrackerWidget
//
//  Created by OpenAI Codex on 2026-04-14.
//

import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

struct HomeScreenTimerModel {
    let snapshot: SharedTimerRuntimeSnapshot
    private let timerService: ExtensionTimerService

    init(
        date: Date = Date(),
        timerService: ExtensionTimerService = ExtensionTimerService()
    ) {
        self.timerService = timerService
        self.snapshot = timerService.widgetSnapshot(at: date)
    }

    var hasVisibleTimer: Bool {
        snapshot.hasTimer && snapshot.primarySeconds > 0
    }

    var progress: CGFloat {
        CGFloat(snapshot.progress)
    }

    var displayText: String {
        timerService.displayText(for: snapshot)
    }

    var ringColor: Color {
        let progress = snapshot.progress
        if progress > 0.5 { return .green }
        if progress > 0.25 { return .yellow }
        return .red
    }
}

struct LiveActivityTimerModel {
    let title: String
    let snapshot: SharedTimerRuntimeSnapshot
    private let timerService: ExtensionTimerService

    init(
        context: ActivityViewContext<TimerActivityAttributes>,
        date: Date = Date(),
        timerService: ExtensionTimerService = ExtensionTimerService()
    ) {
        self.title = context.attributes.title
        self.timerService = timerService
        self.snapshot = timerService.liveActivitySnapshot(context: context, at: date)
    }

    var remainingSeconds: Int {
        snapshot.remainingSeconds ?? 0
    }

    var displayText: String {
        timerService.displayText(for: snapshot)
    }

    var endDate: Date? {
        snapshot.countdownEndDate
    }
}
