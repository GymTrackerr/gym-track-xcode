import Foundation
import SwiftData

@Model
final class DemoSeedProfile {
    var id: UUID = UUID()
    var createdAt: Date
    var updatedAt: Date
    var lastRan: Bool

    var demoUserName: String
    var healthRangeId: String
    var sessionRangeId: String
    var nutritionRangeId: String
    var noiseId: String

    var stepsMean: Double
    var stepsRange: Double
    var activeEnergyMean: Double
    var activeEnergyRange: Double
    var exerciseMinutesMean: Double
    var exerciseMinutesRange: Double
    var restingEnergyMean: Double
    var restingEnergyRange: Double
    var sleepHoursMean: Double
    var sleepHoursRange: Double
    var bodyWeightMean: Double
    var bodyWeightRange: Double
    var nutritionCaloriesMean: Double
    var nutritionCaloriesRange: Double

    init(configuration: DemoSeedConfiguration, lastRan: Bool, createdAt: Date = Date()) {
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.lastRan = lastRan
        self.demoUserName = configuration.demoUserName
        self.healthRangeId = configuration.healthRange.id
        self.sessionRangeId = configuration.sessionRange.id
        self.nutritionRangeId = configuration.nutritionRange.id
        self.noiseId = configuration.noise.id
        self.stepsMean = configuration.healthTargets.steps.mean
        self.stepsRange = configuration.healthTargets.steps.range
        self.activeEnergyMean = configuration.healthTargets.activeEnergyKcal.mean
        self.activeEnergyRange = configuration.healthTargets.activeEnergyKcal.range
        self.exerciseMinutesMean = configuration.healthTargets.exerciseMinutes.mean
        self.exerciseMinutesRange = configuration.healthTargets.exerciseMinutes.range
        self.restingEnergyMean = configuration.healthTargets.restingEnergyKcal.mean
        self.restingEnergyRange = configuration.healthTargets.restingEnergyKcal.range
        self.sleepHoursMean = configuration.healthTargets.sleepHours.mean
        self.sleepHoursRange = configuration.healthTargets.sleepHours.range
        self.bodyWeightMean = configuration.healthTargets.bodyWeightKg.mean
        self.bodyWeightRange = configuration.healthTargets.bodyWeightKg.range
        self.nutritionCaloriesMean = configuration.healthTargets.nutritionCalories.mean
        self.nutritionCaloriesRange = configuration.healthTargets.nutritionCalories.range
    }

    var pickerLabel: String {
        let timestamp = updatedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        return "\(demoUserName) • \(timestamp)"
    }
}

enum DemoSeedProfileStore {
    static func savedProfiles(in context: ModelContext) throws -> [DemoSeedProfile] {
        try context.fetch(
            FetchDescriptor<DemoSeedProfile>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
        )
    }

    static func lastRanProfile(in context: ModelContext) throws -> DemoSeedProfile? {
        try savedProfiles(in: context).first(where: \.lastRan)
    }
}
