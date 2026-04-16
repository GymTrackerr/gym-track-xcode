import Foundation

final class NutritionTargetSyncRepository: BaseSyncRepository, NutritionTargetRepositoryProtocol {
    private let localRepository: NutritionTargetRepositoryProtocol

    init(
        localRepository: NutritionTargetRepositoryProtocol,
        queueStore: SyncQueueStore,
        eligibilityService: SyncEligibilityService
    ) {
        self.localRepository = localRepository
        super.init(queueStore: queueStore, eligibilityService: eligibilityService)
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
