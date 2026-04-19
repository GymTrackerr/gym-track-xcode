//
//  ProgressionRepositoryProtocol.swift
//  GymTracker
//
//  Created by Codex on 2026-04-19.
//

import Foundation

protocol ProgressionRepositoryProtocol {
    func fetchAvailableProfiles(for userId: UUID?) throws -> [ProgressionProfile]
    func fetchArchivedProfiles(for userId: UUID?) throws -> [ProgressionProfile]
    func fetchProfile(id: UUID) throws -> ProgressionProfile?
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
    ) throws -> ProgressionProfile
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
    ) throws -> ProgressionProfile
    func saveChanges(for profile: ProgressionProfile) throws
    func delete(_ profile: ProgressionProfile) throws

    func fetchProgressionExercises(for userId: UUID) throws -> [ProgressionExercise]
    func fetchProgressionExercise(for userId: UUID, exerciseId: UUID) throws -> ProgressionExercise?
    func createProgressionExercise(
        userId: UUID,
        exercise: Exercise,
        profile: ProgressionProfile?,
        targetSetCount: Int,
        targetReps: Int?,
        targetRepsLow: Int?,
        targetRepsHigh: Int?
    ) throws -> ProgressionExercise
    func saveChanges(for progressionExercise: ProgressionExercise) throws
    func delete(_ progressionExercise: ProgressionExercise) throws
}
