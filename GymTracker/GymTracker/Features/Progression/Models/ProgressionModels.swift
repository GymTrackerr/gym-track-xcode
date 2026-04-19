//
//  ProgressionModels.swift
//  GymTracker
//
//  Created by Codex on 2026-04-19.
//

import Foundation
import SwiftData

enum ProgressionType: String, Codable, CaseIterable, Identifiable {
    case linear
    case doubleProgression
    case volume

    var id: String { rawValue }

    var title: String {
        switch self {
        case .linear:
            return "Load Progression"
        case .doubleProgression:
            return "Double Progression"
        case .volume:
            return "Volume Progression"
        }
    }
}

enum ProgressionAssignmentSource: String, Codable, CaseIterable, Identifiable {
    case exerciseOverride
    case programDefault
    case routineDefault
    case userDefault

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exerciseOverride:
            return "Exercise Override"
        case .programDefault:
            return "Program Default"
        case .routineDefault:
            return "Routine Default"
        case .userDefault:
            return "Global Default"
        }
    }
}

@Model
final class ProgressionProfile {
    var id: UUID = UUID()
    var user_id: UUID?
    var name: String
    var miniDescription: String
    var typeRaw: String
    var incrementValue: Double
    var percentageIncreaseStored: Double?
    var incrementUnitRaw: Int
    var setIncrement: Int
    var successThreshold: Int
    var defaultSetsTarget: Int
    var defaultRepsTarget: Int?
    var defaultRepsLow: Int?
    var defaultRepsHigh: Int?
    var isBuiltIn: Bool = false
    var isArchived: Bool = false
    var soft_deleted: Bool = false
    var syncMetaId: UUID? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var timestamp: Date

    init(
        userId: UUID? = nil,
        name: String,
        miniDescription: String,
        type: ProgressionType,
        incrementValue: Double = 5,
        percentageIncrease: Double = 0,
        incrementUnit: WeightUnit = .lb,
        setIncrement: Int = 1,
        successThreshold: Int = 1,
        defaultSetsTarget: Int = 3,
        defaultRepsTarget: Int? = nil,
        defaultRepsLow: Int? = nil,
        defaultRepsHigh: Int? = nil,
        isBuiltIn: Bool = false
    ) {
        let timestamp = Date()
        self.user_id = userId
        self.name = name
        self.miniDescription = miniDescription
        self.typeRaw = type.rawValue
        self.incrementValue = incrementValue
        self.percentageIncreaseStored = max(percentageIncrease, 0)
        self.incrementUnitRaw = incrementUnit.rawValue
        self.setIncrement = max(setIncrement, 1)
        self.successThreshold = max(successThreshold, 1)
        self.defaultSetsTarget = max(defaultSetsTarget, 1)
        self.defaultRepsTarget = defaultRepsTarget
        self.defaultRepsLow = defaultRepsLow
        self.defaultRepsHigh = defaultRepsHigh
        self.isBuiltIn = isBuiltIn
        self.timestamp = timestamp
        self.createdAt = timestamp
        self.updatedAt = timestamp
    }

    var type: ProgressionType {
        get { ProgressionType(rawValue: typeRaw) ?? .linear }
        set { typeRaw = newValue.rawValue }
    }

    var incrementUnit: WeightUnit {
        get { WeightUnit(rawValue: incrementUnitRaw) ?? .lb }
        set { incrementUnitRaw = newValue.rawValue }
    }

    var percentageIncrease: Double {
        get { max(percentageIncreaseStored ?? 0, 0) }
        set { percentageIncreaseStored = max(newValue, 0) }
    }
}

extension ProgressionProfile: SyncTrackedRoot {
    static var syncModelType: SyncModelType { .progressionProfile }
    var syncLinkedItemId: String { id.uuidString.lowercased() }
    var syncSeedDate: Date { timestamp }
    var legacyDeleteBridgeValue: Bool? { isArchived }

    func applyLegacyDeleteBridge(_ value: Bool) {
        isArchived = value
    }
}

@Model
final class ProgressionExercise {
    var id: UUID = UUID()
    var user_id: UUID
    var exerciseId: UUID
    var exerciseNameSnapshot: String
    var progressionProfileId: UUID?
    var progressionNameSnapshot: String?
    var progressionMiniDescriptionSnapshot: String?
    var progressionTypeRaw: String?
    var assignmentSourceRaw: String?
    var targetSetCount: Int
    var targetReps: Int?
    var targetRepsLow: Int?
    var targetRepsHigh: Int?
    var workingWeight: Double?
    var suggestedWeightLow: Double?
    var suggestedWeightHigh: Double?
    var workingWeightUnitRaw: Int
    var lastCompletedCycleWeight: Double?
    var lastCompletedCycleReps: Int?
    var lastCompletedCycleUnitRaw: Int?
    var successCount: Int = 0
    var hasBackfilled: Bool = false
    var backfilledAt: Date?
    var lastEvaluatedSessionId: UUID?
    var soft_deleted: Bool = false
    var syncMetaId: UUID? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var timestamp: Date

    init(
        userId: UUID,
        exerciseId: UUID,
        exerciseName: String,
        profile: ProgressionProfile?,
        targetSetCount: Int = 3,
        targetReps: Int? = nil,
        targetRepsLow: Int? = nil,
        targetRepsHigh: Int? = nil
    ) {
        let timestamp = Date()
        self.user_id = userId
        self.exerciseId = exerciseId
        self.exerciseNameSnapshot = exerciseName
        self.progressionProfileId = profile?.id
        self.progressionNameSnapshot = profile?.name
        self.progressionMiniDescriptionSnapshot = profile?.miniDescription
        self.progressionTypeRaw = profile?.type.rawValue
        self.assignmentSourceRaw = ProgressionAssignmentSource.exerciseOverride.rawValue
        self.targetSetCount = max(targetSetCount, 1)
        self.targetReps = targetReps
        self.targetRepsLow = targetRepsLow
        self.targetRepsHigh = targetRepsHigh
        self.workingWeightUnitRaw = profile?.incrementUnit.rawValue ?? WeightUnit.lb.rawValue
        self.timestamp = timestamp
        self.createdAt = timestamp
        self.updatedAt = timestamp
    }

    var workingWeightUnit: WeightUnit {
        get { WeightUnit(rawValue: workingWeightUnitRaw) ?? .lb }
        set { workingWeightUnitRaw = newValue.rawValue }
    }

    var progressionType: ProgressionType? {
        get {
            guard let progressionTypeRaw else { return nil }
            return ProgressionType(rawValue: progressionTypeRaw)
        }
        set { progressionTypeRaw = newValue?.rawValue }
    }

    var assignmentSource: ProgressionAssignmentSource {
        get {
            guard let assignmentSourceRaw,
                  let source = ProgressionAssignmentSource(rawValue: assignmentSourceRaw) else {
                return .exerciseOverride
            }
            return source
        }
        set { assignmentSourceRaw = newValue.rawValue }
    }

    var isExplicitOverride: Bool {
        assignmentSource == .exerciseOverride
    }

    var lastCompletedCycleUnit: WeightUnit? {
        get {
            guard let lastCompletedCycleUnitRaw else { return nil }
            return WeightUnit(rawValue: lastCompletedCycleUnitRaw)
        }
        set { lastCompletedCycleUnitRaw = newValue?.rawValue }
    }
}

extension ProgressionExercise: SyncTrackedRoot {
    static var syncModelType: SyncModelType { .progressionExercise }
    var syncLinkedItemId: String { id.uuidString.lowercased() }
    var syncSeedDate: Date { timestamp }
}
