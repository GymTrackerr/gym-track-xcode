import Foundation

final class SyncingNutritionTargetRepository: NutritionTargetRepositoryProtocol {
    private let localRepository: NutritionTargetRepositoryProtocol
    private let queueStore: SyncQueueStore
    private let eligibilityService: SyncEligibilityService

    init(
        localRepository: NutritionTargetRepositoryProtocol,
        queueStore: SyncQueueStore,
        eligibilityService: SyncEligibilityService
    ) {
        self.localRepository = localRepository
        self.queueStore = queueStore
        self.eligibilityService = eligibilityService
    }

    func fetchTargets() throws -> [NutritionTarget] {
        try localRepository.fetchTargets()
    }

    func insertNutritionTarget(_ target: NutritionTarget) throws {
        try localRepository.insertNutritionTarget(target)
        SyncQueueMutationWriter.enqueueIfNeeded(
            root: target,
            operation: .create,
            queueStore: queueStore,
            eligibilityService: eligibilityService
        )
    }

    func saveNutritionTarget(_ target: NutritionTarget) throws {
        try localRepository.saveNutritionTarget(target)
        SyncQueueMutationWriter.enqueueIfNeeded(
            root: target,
            operation: .update,
            queueStore: queueStore,
            eligibilityService: eligibilityService
        )
    }
}
