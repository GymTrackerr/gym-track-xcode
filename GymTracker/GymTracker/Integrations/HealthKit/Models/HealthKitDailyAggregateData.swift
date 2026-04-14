import Foundation
import SwiftData

@Model
final class HealthKitDailyAggregateData {
    static let defaultSchemaVersion: Double = 1.0
    static let currentSchemaVersion: Double = 1.2

    @Attribute(.unique) var cacheKey: String
    var userId: String
    var dayKey: String
    var dayStart: Date
    var steps: Double
    var activeEnergyKcal: Double
    var restingEnergyKcal: Double
    var exerciseMinutes: Double?
    var standHours: Int?
    var moveGoalKcal: Double?
    var exerciseGoalMinutes: Double?
    var standGoalHours: Int?
    var sleepSeconds: TimeInterval
    var bodyWeightKg: Double = 0
    var schemaVersion: Double = 1.2
    var lastRefreshedAt: Date
    var isToday: Bool

    init(
        userId: String,
        dayKey: String,
        dayStart: Date,
        steps: Double,
        activeEnergyKcal: Double,
        restingEnergyKcal: Double,
        exerciseMinutes: Double? = nil,
        standHours: Int? = nil,
        moveGoalKcal: Double? = nil,
        exerciseGoalMinutes: Double? = nil,
        standGoalHours: Int? = nil,
        sleepSeconds: TimeInterval,
        bodyWeightKg: Double,
        schemaVersion: Double = HealthKitDailyAggregateData.defaultSchemaVersion,
        lastRefreshedAt: Date = .distantPast,
        isToday: Bool = false
    ) {
        self.cacheKey = "\(userId)|\(dayKey)"
        self.userId = userId
        self.dayKey = dayKey
        self.dayStart = dayStart
        self.steps = steps
        self.activeEnergyKcal = activeEnergyKcal
        self.restingEnergyKcal = restingEnergyKcal
        self.exerciseMinutes = exerciseMinutes
        self.standHours = standHours
        self.moveGoalKcal = moveGoalKcal
        self.exerciseGoalMinutes = exerciseGoalMinutes
        self.standGoalHours = standGoalHours
        self.sleepSeconds = sleepSeconds
        self.bodyWeightKg = bodyWeightKg
        self.schemaVersion = schemaVersion
        self.lastRefreshedAt = lastRefreshedAt
        self.isToday = isToday
    }

    var id: String { "\(userId)|\(dayKey)" }
}
