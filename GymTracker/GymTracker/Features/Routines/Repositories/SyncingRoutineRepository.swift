import Foundation

final class SyncingRoutineRepository: RoutineRepositoryProtocol {
    private let localRepository: RoutineRepositoryProtocol
    private let queueStore: SyncQueueStore
    private let eligibilityService: SyncEligibilityService

    init(
        localRepository: RoutineRepositoryProtocol,
        queueStore: SyncQueueStore,
        eligibilityService: SyncEligibilityService
    ) {
        self.localRepository = localRepository
        self.queueStore = queueStore
        self.eligibilityService = eligibilityService
    }

    func fetchActiveRoutines(for userId: UUID) throws -> [Routine] { try localRepository.fetchActiveRoutines(for: userId) }
    func fetchArchivedRoutines(for userId: UUID) throws -> [Routine] { try localRepository.fetchArchivedRoutines(for: userId) }
    func fetchAllRoutines() throws -> [Routine] { try localRepository.fetchAllRoutines() }

    func createRoutine(name: String, userId: UUID, order: Int) throws -> Routine {
        let routine = try localRepository.createRoutine(name: name, userId: userId, order: order)
        enqueue(for: routine, operation: .create)
        return routine
    }

    func setAliases(_ aliases: [String], for routine: Routine) throws {
        try localRepository.setAliases(aliases, for: routine)
        enqueue(for: routine, operation: .update)
    }

    func reinsertOrRestore(_ routine: Routine) throws {
        let operation: SyncQueueOperation = routine.isArchived ? .restore : .create
        try localRepository.reinsertOrRestore(routine)
        enqueue(for: routine, operation: operation)
    }

    func delete(_ routine: Routine) throws {
        try localRepository.delete(routine)
        enqueue(for: routine, operation: .softDelete)
    }

    func restore(_ routine: Routine) throws {
        try localRepository.restore(routine)
        enqueue(for: routine, operation: .restore)
    }

    func willArchiveOnDelete(_ routine: Routine) -> Bool { localRepository.willArchiveOnDelete(routine) }

    func renumber(_ routines: [Routine]) throws {
        try localRepository.renumber(routines)
        for routine in routines {
            enqueue(for: routine, operation: .update)
        }
    }

    func renumberExerciseSplits(in routine: Routine) throws {
        try localRepository.renumberExerciseSplits(in: routine)
        enqueue(for: routine, operation: .update)
    }

    func addExercise(to routine: Routine, exercise: Exercise) throws -> ExerciseSplitDay? {
        let split = try localRepository.addExercise(to: routine, exercise: exercise)
        enqueue(for: routine, operation: .update)
        return split
    }

    func removeExercise(from routine: Routine, exercise: Exercise) throws {
        try localRepository.removeExercise(from: routine, exercise: exercise)
        enqueue(for: routine, operation: .update)
    }

    func removeExerciseSplits(from routine: Routine, splitIds: [UUID]) throws {
        try localRepository.removeExerciseSplits(from: routine, splitIds: splitIds)
        enqueue(for: routine, operation: .update)
    }

    func moveExercises(in routine: Routine, from source: IndexSet, to destination: Int) throws {
        try localRepository.moveExercises(in: routine, from: source, to: destination)
        enqueue(for: routine, operation: .update)
    }

    func reinsertExerciseSplit(_ exerciseSplit: ExerciseSplitDay, into routine: Routine) throws {
        try localRepository.reinsertExerciseSplit(exerciseSplit, into: routine)
        enqueue(for: routine, operation: .update)
    }

    func saveChanges() throws { try localRepository.saveChanges() }

    private func enqueue(for routine: Routine, operation: SyncQueueOperation) {
        SyncQueueMutationWriter.enqueueIfNeeded(
            root: routine,
            operation: operation,
            queueStore: queueStore,
            eligibilityService: eligibilityService
        )
    }
}
