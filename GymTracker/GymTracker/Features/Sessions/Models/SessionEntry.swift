//
//  SessionEntry.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-04.
//

import Foundation
import SwiftData

@Model
final class SessionEntry {
//    @Attribute(.unique)
    var id: UUID = UUID()
    var order: Int
    
    var isCompleted: Bool = false
    
    var exercise: Exercise
    
    var session: Session
    
    @Relationship(deleteRule: .cascade)
    var sets: [SessionSet]

    var appliedProgressionProfileId: UUID? = nil
    var appliedProgressionNameSnapshot: String? = nil
    var appliedProgressionMiniDescriptionSnapshot: String? = nil
    var appliedProgressionTypeRaw: String? = nil
    var appliedTargetSetCount: Int? = nil
    var appliedTargetReps: Int? = nil
    var appliedTargetRepsLow: Int? = nil
    var appliedTargetRepsHigh: Int? = nil
    var appliedTargetWeight: Double? = nil
    var appliedTargetWeightUnitRaw: Int? = nil
    
    var exercise_id: UUID { exercise.id }
    var session_id: UUID { session.id }
    
    // construct without split day
    init(order: Int, session: Session, exercise: Exercise) {
        self.order = order
        self.session = session
        self.exercise = exercise
        self.sets = []
    }
    
    // construct via exerciseSplitDay
    convenience init(session: Session, exerciseSplitDay: ExerciseSplitDay) {
        self.init(order: exerciseSplitDay.order, session: session, exercise: exerciseSplitDay.exercise)
    }

    var appliedTargetWeightUnit: WeightUnit? {
        get {
            guard let appliedTargetWeightUnitRaw else { return nil }
            return WeightUnit(rawValue: appliedTargetWeightUnitRaw)
        }
        set {
            appliedTargetWeightUnitRaw = newValue?.rawValue
        }
    }

    var hasProgressionSnapshot: Bool {
        appliedProgressionProfileId != nil ||
        appliedProgressionNameSnapshot != nil ||
        appliedTargetSetCount != nil ||
        appliedTargetReps != nil ||
        appliedTargetRepsLow != nil ||
        appliedTargetRepsHigh != nil ||
        appliedTargetWeight != nil
    }

    @discardableResult
    func applyProgressionSnapshot(
        progressionExercise: ProgressionExercise,
        profile: ProgressionProfile?,
        suggestedWeight: Double?,
        suggestedWeightUnit: WeightUnit?
    ) -> Bool {
        let previousState = (
            appliedProgressionProfileId,
            appliedProgressionNameSnapshot,
            appliedProgressionMiniDescriptionSnapshot,
            appliedProgressionTypeRaw,
            appliedTargetSetCount,
            appliedTargetReps,
            appliedTargetRepsLow,
            appliedTargetRepsHigh,
            appliedTargetWeight,
            appliedTargetWeightUnitRaw
        )

        appliedProgressionProfileId = progressionExercise.progressionProfileId
        appliedProgressionNameSnapshot = progressionExercise.progressionNameSnapshot ?? profile?.name
        appliedProgressionMiniDescriptionSnapshot = progressionExercise.progressionMiniDescriptionSnapshot ?? profile?.miniDescription
        appliedProgressionTypeRaw = progressionExercise.progressionTypeRaw ?? profile?.type.rawValue
        appliedTargetSetCount = progressionExercise.targetSetCount
        appliedTargetReps = progressionExercise.targetReps
        appliedTargetRepsLow = progressionExercise.targetRepsLow
        appliedTargetRepsHigh = progressionExercise.targetRepsHigh
        appliedTargetWeight = suggestedWeight
        appliedTargetWeightUnit = suggestedWeightUnit

        let currentState = (
            appliedProgressionProfileId,
            appliedProgressionNameSnapshot,
            appliedProgressionMiniDescriptionSnapshot,
            appliedProgressionTypeRaw,
            appliedTargetSetCount,
            appliedTargetReps,
            appliedTargetRepsLow,
            appliedTargetRepsHigh,
            appliedTargetWeight,
            appliedTargetWeightUnitRaw
        )

        return previousState.0 != currentState.0 ||
            previousState.1 != currentState.1 ||
            previousState.2 != currentState.2 ||
            previousState.3 != currentState.3 ||
            previousState.4 != currentState.4 ||
            previousState.5 != currentState.5 ||
            previousState.6 != currentState.6 ||
            previousState.7 != currentState.7 ||
            previousState.8 != currentState.8 ||
            previousState.9 != currentState.9
    }

    func clearProgressionSnapshot() {
        appliedProgressionProfileId = nil
        appliedProgressionNameSnapshot = nil
        appliedProgressionMiniDescriptionSnapshot = nil
        appliedProgressionTypeRaw = nil
        appliedTargetSetCount = nil
        appliedTargetReps = nil
        appliedTargetRepsLow = nil
        appliedTargetRepsHigh = nil
        appliedTargetWeight = nil
        appliedTargetWeightUnit = nil
    }
}
