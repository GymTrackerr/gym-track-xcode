//
//  LocalRoutineRepository.swift
//  GymTracker
//
//  Created by Codex on 2026-04-15.
//

import Foundation
import SwiftData
import SwiftUI

final class LocalRoutineRepository: RoutineRepositoryProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchActiveRoutines(for userId: UUID) throws -> [Routine] {
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate<Routine> { routine in
                routine.user_id == userId && routine.soft_deleted == false && routine.isArchived == false
            },
            sortBy: [SortDescriptor(\.order)]
        )
        let routines = try modelContext.fetch(descriptor)
        if try SyncRootMetadataManager.prepareForRead(routines, in: modelContext) {
            try modelContext.save()
        }
        return routines
    }

    func fetchArchivedRoutines(for userId: UUID) throws -> [Routine] {
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate<Routine> { routine in
                routine.user_id == userId && (routine.soft_deleted == true || routine.isArchived == true)
            },
            sortBy: [SortDescriptor(\.order)]
        )
        let routines = try modelContext.fetch(descriptor)
        if try SyncRootMetadataManager.prepareForRead(routines, in: modelContext) {
            try modelContext.save()
        }
        return routines
    }

    func fetchAllRoutines() throws -> [Routine] {
        let routines = try modelContext.fetch(FetchDescriptor<Routine>())
        if try SyncRootMetadataManager.prepareForRead(routines, in: modelContext) {
            try modelContext.save()
        }
        return routines
    }

    func createRoutine(name: String, userId: UUID, order: Int) throws -> Routine {
        let routine = Routine(order: order, name: name, user_id: userId)
        modelContext.insert(routine)
        try SyncRootMetadataManager.markCreated(routine, in: modelContext)
        try modelContext.save()
        return routine
    }

    func setAliases(_ aliases: [String], for routine: Routine) throws {
        routine.aliases = Array(Set(aliases)).sorted()
        try SyncRootMetadataManager.markUpdated(routine, in: modelContext)
        try modelContext.save()
    }

    func reinsertOrRestore(_ routine: Routine) throws {
        if routine.isArchived {
            try SyncRootMetadataManager.markRestored(routine, in: modelContext)
        } else {
            modelContext.insert(routine)
            try SyncRootMetadataManager.markCreated(routine, in: modelContext)
        }
        try modelContext.save()
    }

    func delete(_ routine: Routine) throws {
        try SyncRootMetadataManager.markSoftDeleted(routine, in: modelContext)
        try modelContext.save()
    }

    func restore(_ routine: Routine) throws {
        try SyncRootMetadataManager.markRestored(routine, in: modelContext)
        try modelContext.save()
    }

    func willArchiveOnDelete(_ routine: Routine) -> Bool {
        !routine.sessions.isEmpty
    }

    func renumber(_ routines: [Routine]) throws {
        for (index, routine) in routines.enumerated() {
            routine.order = index
            try SyncRootMetadataManager.markUpdated(routine, in: modelContext)
        }
        try modelContext.save()
    }

    func renumberExerciseSplits(in routine: Routine) throws {
        let exercises = routine.exerciseSplits.sorted { $0.order < $1.order }
        for (index, exercise) in exercises.enumerated() {
            exercise.order = index
        }
        try SyncRootMetadataManager.markUpdated(routine, in: modelContext)
        try modelContext.save()
    }

    func addExercise(to routine: Routine, exercise: Exercise) throws -> ExerciseSplitDay? {
        guard !routine.exerciseSplits.contains(where: { $0.exercise.id == exercise.id }) else { return nil }
        let newExerciseSplit = ExerciseSplitDay(
            order: routine.exerciseSplits.count,
            routine: routine,
            exercise: exercise
        )
        modelContext.insert(newExerciseSplit)
        routine.exerciseSplits.append(newExerciseSplit)
        try SyncRootMetadataManager.markUpdated(routine, in: modelContext)
        try modelContext.save()
        return newExerciseSplit
    }

    func removeExercise(from routine: Routine, exercise: Exercise) throws {
        if let exerciseSplit = routine.exerciseSplits.first(where: { $0.exercise == exercise }) {
            routine.exerciseSplits.removeAll { $0.id == exerciseSplit.id }
        }
        try SyncRootMetadataManager.markUpdated(routine, in: modelContext)
        try modelContext.save()
    }

    func removeExerciseSplits(from routine: Routine, splitIds: [UUID]) throws {
        let validSplits = routine.exerciseSplits.filter { splitIds.contains($0.id) }
        for split in validSplits {
            routine.exerciseSplits.removeAll { $0.id == split.id }
        }
        try SyncRootMetadataManager.markUpdated(routine, in: modelContext)
        try modelContext.save()
        try renumberExerciseSplits(in: routine)
    }

    func moveExercises(in routine: Routine, from source: IndexSet, to destination: Int) throws {
        var exercises = routine.exerciseSplits.sorted { $0.order < $1.order }
        exercises.move(fromOffsets: source, toOffset: destination)
        for (index, exercise) in exercises.enumerated() {
            exercise.order = index
        }
        try SyncRootMetadataManager.markUpdated(routine, in: modelContext)
        try modelContext.save()
    }

    func reinsertExerciseSplit(_ exerciseSplit: ExerciseSplitDay, into routine: Routine) throws {
        if !routine.exerciseSplits.contains(where: { $0.id == exerciseSplit.id }) {
            routine.exerciseSplits.append(exerciseSplit)
        }
        try SyncRootMetadataManager.markUpdated(routine, in: modelContext)
        try modelContext.save()
        try renumberExerciseSplits(in: routine)
    }

    func saveChanges() throws {
        try modelContext.save()
    }
}
