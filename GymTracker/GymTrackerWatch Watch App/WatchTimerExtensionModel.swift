//
//  WatchTimerExtensionModel.swift
//  GymTrackerWatch Watch App
//
//  Created by OpenAI Codex on 2026-04-14.
//

import Foundation
import Combine

final class WatchTimerExtensionModel: ObservableObject {
    @Published private(set) var snapshot: SharedTimerRuntimeSnapshot
    @Published private(set) var isReachable: Bool = false

    private let sessionListener: WatchSessionListener
    private let timerService: ExtensionTimerService
    private var cancellables = Set<AnyCancellable>()

    init(
        sessionListener: WatchSessionListener = WatchSessionListener(),
        timerService: ExtensionTimerService = ExtensionTimerService()
    ) {
        self.sessionListener = sessionListener
        self.timerService = timerService
        self.snapshot = timerService.watchSnapshot(
            timer: nil,
            pendingLength: sessionListener.pendingLength
        )

        bind()
    }

    var hasActiveTimer: Bool {
        snapshot.hasTimer
    }

    var timerDisplayText: String {
        timerService.displayText(for: snapshot)
    }

    var progress: Double {
        snapshot.progress
    }

    var isPaused: Bool {
        snapshot.isPaused
    }

    func addToTimer(seconds: Int) {
        sessionListener.addToTimer(seconds: seconds)
    }

    func startTimer() {
        sessionListener.startTimer()
    }

    func pauseTimer() {
        sessionListener.pauseTimer()
    }

    func resumeTimer() {
        sessionListener.resumeTimer()
    }

    func stopTimer(delete: Bool = false) {
        sessionListener.stopTimer(delete: delete)
    }

    private func bind() {
        Publishers.CombineLatest3(
            sessionListener.$timer,
            sessionListener.$pendingLength,
            sessionListener.$isReachable
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] timer, pendingLength, isReachable in
            guard let self else { return }
            self.snapshot = self.timerService.watchSnapshot(
                timer: timer,
                pendingLength: pendingLength
            )
            self.isReachable = isReachable
        }
        .store(in: &cancellables)
    }
}
