//
//  LocalProgressionRepository.swift
//  GymTracker
//
//  Created by Codex on 2026-04-19.
//

import Foundation
import SwiftData

final class LocalProgressionRepository: ProgressionRepositoryProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAvailableProfiles(for userId: UUID?) throws -> [ProgressionProfile] {
        let descriptor = FetchDescriptor<ProgressionProfile>(
            predicate: #Predicate<ProgressionProfile> { profile in
                profile.soft_deleted == false && profile.isArchived == false
            }
        )
        let profiles = try modelContext.fetch(descriptor)
        if try SyncRootMetadataManager.prepareForRead(profiles, in: modelContext) {
            try modelContext.save()
        }

        return profiles
            .filter { profile in
                guard let userId else { return true }
                return profile.user_id == nil || profile.user_id == userId
            }
            .sorted { lhs, rhs in
                if lhs.isBuiltIn != rhs.isBuiltIn {
                    return lhs.isBuiltIn && !rhs.isBuiltIn
                }
                let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if nameComparison != .orderedSame {
                    return nameComparison == .orderedAscending
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    func fetchArchivedProfiles(for userId: UUID?) throws -> [ProgressionProfile] {
        let descriptor = FetchDescriptor<ProgressionProfile>(
            predicate: #Predicate<ProgressionProfile> { profile in
                profile.soft_deleted == true || profile.isArchived == true
            }
        )
        let profiles = try modelContext.fetch(descriptor)
        if try SyncRootMetadataManager.prepareForRead(profiles, in: modelContext) {
            try modelContext.save()
        }

        return profiles
            .filter { profile in
                guard let userId else { return true }
                return profile.user_id == nil || profile.user_id == userId
            }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    func fetchProfile(id: UUID) throws -> ProgressionProfile? {
        let descriptor = FetchDescriptor<ProgressionProfile>(
            predicate: #Predicate<ProgressionProfile> { profile in
                profile.id == id
            }
        )
        let profile = try modelContext.fetch(descriptor).first
        if let profile, try SyncRootMetadataManager.prepareForRead(profile, in: modelContext) {
            try modelContext.save()
        }
        return profile
    }

    func upsertBuiltInProfile(
        name: String,
        miniDescription: String,
        type: ProgressionType,
        incrementValue: Double,
        incrementUnit: WeightUnit,
        setIncrement: Int,
        successThreshold: Int,
        defaultSetsTarget: Int,
        defaultRepsTarget: Int?,
        defaultRepsLow: Int?,
        defaultRepsHigh: Int?
    ) throws -> ProgressionProfile {
        let descriptor = FetchDescriptor<ProgressionProfile>(
            predicate: #Predicate<ProgressionProfile> { profile in
                profile.isBuiltIn == true && profile.name == name
            }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }

        let profile = ProgressionProfile(
            name: name,
            miniDescription: miniDescription,
            type: type,
            incrementValue: incrementValue,
            incrementUnit: incrementUnit,
            setIncrement: setIncrement,
            successThreshold: successThreshold,
            defaultSetsTarget: defaultSetsTarget,
            defaultRepsTarget: defaultRepsTarget,
            defaultRepsLow: defaultRepsLow,
            defaultRepsHigh: defaultRepsHigh,
            isBuiltIn: true
        )
        modelContext.insert(profile)
        try SyncRootMetadataManager.markCreated(profile, in: modelContext)
        try modelContext.save()
        return profile
    }

    func createProfile(
        userId: UUID,
        name: String,
        miniDescription: String,
        type: ProgressionType,
        incrementValue: Double,
        incrementUnit: WeightUnit,
        setIncrement: Int,
        successThreshold: Int,
        defaultSetsTarget: Int,
        defaultRepsTarget: Int?,
        defaultRepsLow: Int?,
        defaultRepsHigh: Int?
    ) throws -> ProgressionProfile {
        let profile = ProgressionProfile(
            userId: userId,
            name: name,
            miniDescription: miniDescription,
            type: type,
            incrementValue: incrementValue,
            incrementUnit: incrementUnit,
            setIncrement: setIncrement,
            successThreshold: successThreshold,
            defaultSetsTarget: defaultSetsTarget,
            defaultRepsTarget: defaultRepsTarget,
            defaultRepsLow: defaultRepsLow,
            defaultRepsHigh: defaultRepsHigh,
            isBuiltIn: false
        )
        modelContext.insert(profile)
        try SyncRootMetadataManager.markCreated(profile, in: modelContext)
        try modelContext.save()
        return profile
    }

    func saveChanges(for profile: ProgressionProfile) throws {
        try SyncRootMetadataManager.markUpdated(profile, in: modelContext)
        try modelContext.save()
    }

    func delete(_ profile: ProgressionProfile) throws {
        try SyncRootMetadataManager.markSoftDeleted(profile, in: modelContext)
        try modelContext.save()
    }

    func fetchProgressionExercises(for userId: UUID) throws -> [ProgressionExercise] {
        let descriptor = FetchDescriptor<ProgressionExercise>(
            predicate: #Predicate<ProgressionExercise> { progressionExercise in
                progressionExercise.user_id == userId && progressionExercise.soft_deleted == false
            }
        )
        let progressionExercises = try modelContext.fetch(descriptor)
        if try SyncRootMetadataManager.prepareForRead(progressionExercises, in: modelContext) {
            try modelContext.save()
        }
        return progressionExercises.sorted { lhs, rhs in
            let nameComparison = lhs.exerciseNameSnapshot.localizedCaseInsensitiveCompare(rhs.exerciseNameSnapshot)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    func fetchProgressionExercise(for userId: UUID, exerciseId: UUID) throws -> ProgressionExercise? {
        let descriptor = FetchDescriptor<ProgressionExercise>(
            predicate: #Predicate<ProgressionExercise> { progressionExercise in
                progressionExercise.user_id == userId && progressionExercise.exerciseId == exerciseId && progressionExercise.soft_deleted == false
            }
        )
        let progressionExercise = try modelContext.fetch(descriptor).first
        if let progressionExercise, try SyncRootMetadataManager.prepareForRead(progressionExercise, in: modelContext) {
            try modelContext.save()
        }
        return progressionExercise
    }

    func createProgressionExercise(
        userId: UUID,
        exercise: Exercise,
        profile: ProgressionProfile?,
        targetSetCount: Int,
        targetReps: Int?,
        targetRepsLow: Int?,
        targetRepsHigh: Int?
    ) throws -> ProgressionExercise {
        let progressionExercise = ProgressionExercise(
            userId: userId,
            exerciseId: exercise.id,
            exerciseName: exercise.name,
            profile: profile,
            targetSetCount: targetSetCount,
            targetReps: targetReps,
            targetRepsLow: targetRepsLow,
            targetRepsHigh: targetRepsHigh
        )
        modelContext.insert(progressionExercise)
        try SyncRootMetadataManager.markCreated(progressionExercise, in: modelContext)
        try modelContext.save()
        return progressionExercise
    }

    func saveChanges(for progressionExercise: ProgressionExercise) throws {
        try SyncRootMetadataManager.markUpdated(progressionExercise, in: modelContext)
        try modelContext.save()
    }

    func delete(_ progressionExercise: ProgressionExercise) throws {
        try SyncRootMetadataManager.markSoftDeleted(progressionExercise, in: modelContext)
        try modelContext.save()
    }
}
