//
//  SyncCoordinator.swift
//  GymTracker
//
//  Created by Codex on 2026-04-15.
//

import Foundation
import Combine

final class SyncCoordinator: ObservableObject {
    enum RunState: String {
        case idle
        case monitoring
        case processing
    }

    @Published private(set) var runState: RunState = .idle
    @Published private(set) var lastTriggerReason: String?
    @Published private(set) var lastEvaluationAt: Date?

    private let queueStore: SyncQueueStore
    private let eligibilityService: SyncEligibilityService
    private let worker: SyncWorker
    private var cancellables = Set<AnyCancellable>()
    private var started = false
    private var evaluationTask: Task<Void, Never>?

    init(
        queueStore: SyncQueueStore,
        eligibilityService: SyncEligibilityService,
        worker: SyncWorker
    ) {
        self.queueStore = queueStore
        self.eligibilityService = eligibilityService
        self.worker = worker
    }

    func start() {
        guard started == false else { return }
        started = true
        runState = .monitoring

        eligibilityService.$snapshot
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.scheduleEvaluation(reason: "eligibilityChanged")
            }
            .store(in: &cancellables)

        scheduleEvaluation(reason: "startup")
    }

    func triggerSync(reason: String) {
        scheduleEvaluation(reason: reason)
    }

    private func scheduleEvaluation(reason: String) {
        lastTriggerReason = reason
        evaluationTask?.cancel()
        evaluationTask = Task { [weak self] in
            await self?.evaluate()
        }
    }

    private func evaluate() async {
        let timestamp = Date()
        lastEvaluationAt = timestamp

        try? queueStore.purgeDeadLetters(olderThan: timestamp.addingTimeInterval(-30 * 24 * 60 * 60))

        guard eligibilityService.isProcessingEligible else {
            runState = .monitoring
            return
        }

        runState = .processing
        defer { runState = .monitoring }

        _ = try? worker.processNextEligibleItem(referenceDate: timestamp)
    }
}
