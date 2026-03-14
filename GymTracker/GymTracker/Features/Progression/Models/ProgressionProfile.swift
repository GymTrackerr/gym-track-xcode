import Foundation
import SwiftData

enum ProgressionType: Int, CaseIterable, Identifiable {
    case linear = 0
    case doubleProgression = 1
    case custom = 2

    var id: Int { rawValue }
}

enum ProgressionIncrementUnit: Int, CaseIterable, Identifiable {
    case pounds = 0
    case kilograms = 1

    var id: Int { rawValue }
}

enum ProgressionSuccessPolicy: Int, CaseIterable, Identifiable {
    case allTargetsMet = 0
    case anyTopSetMet = 1

    var id: Int { rawValue }
}

@Model
final class ProgressionProfile {
    var id: UUID = UUID()
    var user_id: UUID?
    var name: String

    var type: Int
    var requiredSuccessSessions: Int
    var incrementValue: Double
    var incrementUnit: Int
    var successPolicy: Int

    var defaultRepsTarget: Int?
    var defaultRepsLow: Int?
    var defaultRepsHigh: Int?
    var isBuiltIn: Bool = false
    var isArchived: Bool = false

    @Relationship(deleteRule: .nullify, inverse: \ProgramDayExerciseOverride.progression)
    var overrides: [ProgramDayExerciseOverride]

    @Relationship(deleteRule: .nullify, inverse: \ProgressionState.progression)
    var states: [ProgressionState]

    var progressionType: ProgressionType {
        get { ProgressionType(rawValue: type) ?? .custom }
        set { type = newValue.rawValue }
    }

    var progressionIncrementUnit: ProgressionIncrementUnit {
        get { ProgressionIncrementUnit(rawValue: incrementUnit) ?? .pounds }
        set { incrementUnit = newValue.rawValue }
    }

    var progressionSuccessPolicy: ProgressionSuccessPolicy {
        get { ProgressionSuccessPolicy(rawValue: successPolicy) ?? .allTargetsMet }
        set { successPolicy = newValue.rawValue }
    }

    init(
        user_id: UUID? = nil,
        name: String,
        type: ProgressionType,
        requiredSuccessSessions: Int,
        incrementValue: Double,
        incrementUnit: ProgressionIncrementUnit,
        successPolicy: ProgressionSuccessPolicy,
        defaultRepsTarget: Int? = nil,
        defaultRepsLow: Int? = nil,
        defaultRepsHigh: Int? = nil,
        isBuiltIn: Bool = false,
        isArchived: Bool = false
    ) {
        self.user_id = user_id
        self.name = name
        self.type = type.rawValue
        self.requiredSuccessSessions = requiredSuccessSessions
        self.incrementValue = incrementValue
        self.incrementUnit = incrementUnit.rawValue
        self.successPolicy = successPolicy.rawValue
        self.defaultRepsTarget = defaultRepsTarget
        self.defaultRepsLow = defaultRepsLow
        self.defaultRepsHigh = defaultRepsHigh
        self.isBuiltIn = isBuiltIn
        self.isArchived = isArchived
        self.overrides = []
        self.states = []
    }
}
