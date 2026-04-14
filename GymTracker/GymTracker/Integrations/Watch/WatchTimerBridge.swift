//
//  WatchTimerBridge.swift
//  GymTracker
//
//  Created by OpenAI Codex on 2026-04-14.
//

#if os(iOS)
import Combine
import Foundation

final class WatchTimerBridge: WatchTimerControlling {
    private let timerService: TimerService

    init(timerService: TimerService) {
        self.timerService = timerService
    }

    var timerPublisher: AnyPublisher<WatchTimerSnapshot?, Never> {
        timerService.$timer
            .map { $0?.toWatchSnapshot() }
            .eraseToAnyPublisher()
    }

    var pendingLengthPublisher: AnyPublisher<Int, Never> {
        timerService.$pendingLength.eraseToAnyPublisher()
    }

    var timerSnapshot: WatchTimerSnapshot? {
        timerService.timer?.toWatchSnapshot()
    }

    var pendingLength: Int {
        get { timerService.pendingLength }
        set { timerService.pendingLength = newValue }
    }

    func start(length: Int?) {
        if let length {
            pendingLength = length
        }
        timerService.start()
    }

    func pause() {
        timerService.pause()
    }

    func resume() {
        timerService.resume()
    }

    func stop(delete: Bool) {
        timerService.stop(delete: delete)
    }
}
#endif
