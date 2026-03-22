import Foundation
import SwiftData

@Model
final class HealthKitDailySummaryCache {
    @Attribute(.unique) var cacheKey: String
    var userId: String
    var dayKey: String
    var dayStart: Date
    var steps: Double
    var activeEnergyKcal: Double
    var restingEnergyKcal: Double
    var sleepSeconds: Double
    var lastRefreshedAt: Date
    var isComplete: Bool
    var sourceVersion: Int

    init(
        userId: String,
        dayKey: String,
        dayStart: Date,
        steps: Double,
        activeEnergyKcal: Double,
        restingEnergyKcal: Double,
        sleepSeconds: Double,
        lastRefreshedAt: Date,
        isComplete: Bool,
        sourceVersion: Int
    ) {
        self.cacheKey = "\(userId)|\(dayKey)"
        self.userId = userId
        self.dayKey = dayKey
        self.dayStart = dayStart
        self.steps = steps
        self.activeEnergyKcal = activeEnergyKcal
        self.restingEnergyKcal = restingEnergyKcal
        self.sleepSeconds = sleepSeconds
        self.lastRefreshedAt = lastRefreshedAt
        self.isComplete = isComplete
        self.sourceVersion = sourceVersion
    }
}
