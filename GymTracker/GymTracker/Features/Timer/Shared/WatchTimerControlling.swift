//
//  WatchTimerControlling.swift
//  GymTracker
//
//  Created by OpenAI Codex on 2026-04-14.
//

import Combine
import Foundation

protocol WatchTimerControlling: AnyObject {
    var timerPublisher: AnyPublisher<WatchTimerSnapshot?, Never> { get }
    var pendingLengthPublisher: AnyPublisher<Int, Never> { get }

    var timerSnapshot: WatchTimerSnapshot? { get }
    var pendingLength: Int { get set }

    func start(length: Int?)
    func pause()
    func resume()
    func stop(delete: Bool)
}
