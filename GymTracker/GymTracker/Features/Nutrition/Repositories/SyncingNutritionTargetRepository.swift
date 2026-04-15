import Foundation

final class SyncingNutritionTargetRepository: BaseSyncRepository, NutritionTargetRepositoryProtocol {
    private let localRepository: NutritionTargetRepositoryProtocol

    init(
        localRepository: NutritionTargetRepositoryProtocol,
        queueStore: SyncQueueStore,
        eligibilityService: SyncEligibilityService
    ) {
        super.init(queueStore: queueStore, eligibilityService: eligibilityService)
        self.localRepository = localRepository
    }

    func fetchTargets() throws -> [NutritionTarget] {
        try localRepository.fetchTargets()
    }

    func insertNutritionTarget(_ target: NutritionTarget) throws {
        try localRepository.insertNutritionTarget(target)
        enqueueRootMutationIfNeeded(root: target, operation: .create)
    }

    func saveNutritionTarget(_ target: NutritionTarget) throws {
        try localRepository.saveNutritionTarget(target)
        enqueueRootMutationIfNeeded(root: target, operation: .update)
    }
}
