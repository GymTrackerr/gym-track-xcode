import Foundation
import SwiftData
import Combine

struct EnergyBalanceSnapshot {
    let day: Date
    let intakeCalories: Double
    let usedCalories: Double
    let deficitSurplusCalories: Double
}

@MainActor
final class HealthMetricsService: ServiceBase, ObservableObject {
    @Published private(set) var lastSnapshot: EnergyBalanceSnapshot?

    private let dailyStore: HealthKitDailyStore
    private let nutritionService: NutritionService
    private let dateNormalizer: HealthKitDateNormalizer

    init(
        context: ModelContext,
        dailyStore: HealthKitDailyStore,
        nutritionService: NutritionService,
        dateNormalizer: HealthKitDateNormalizer
    ) {
        self.dailyStore = dailyStore
        self.nutritionService = nutritionService
        self.dateNormalizer = dateNormalizer
        super.init(context: context)
    }

    func totalUsedCalories(for day: Date, userId: String) async throws -> Double {
        let summary = try await dailyStore.dailySummary(for: day, userId: userId, policy: .refreshIfStale)
        return summary.activeEnergyKcal + summary.restingEnergyKcal
    }

    func deficitSurplus(for day: Date, userId: String) async throws -> Double {
        let used = try await totalUsedCalories(for: day, userId: userId)
        let intake = try nutritionService.calorieIntake(for: day)
        return used - intake
    }

    func sevenDayAverageDeficit(endingOn endDate: Date, userId: String) async throws -> Double {
        let healthData = try await dailyStore.dailySummaries(
            endingOn: endDate,
            days: 7,
            userId: userId,
            policy: .refreshIfStale
        )
        let intakeSeries = try nutritionService.calorieIntakeSeries(endingOn: endDate, days: 7)
        let intakeByDayKey = Dictionary(uniqueKeysWithValues: intakeSeries.map { point in
            (dateNormalizer.dayKey(point.date), point.kcal)
        })

        let deficits = healthData.map { day in
            let used = day.activeEnergyKcal + day.restingEnergyKcal
            let intake = intakeByDayKey[day.dayKey] ?? 0
            return used - intake
        }

        guard !deficits.isEmpty else { return 0 }
        let total = deficits.reduce(0, +)
        return total / Double(deficits.count)
    }

    func energyBalanceSnapshot(for day: Date, userId: String) async throws -> EnergyBalanceSnapshot {
        let normalizedDay = dateNormalizer.startOfDay(day)
        let intake = try nutritionService.calorieIntake(for: normalizedDay)
        let used = try await totalUsedCalories(for: normalizedDay, userId: userId)
        let snapshot = EnergyBalanceSnapshot(
            day: normalizedDay,
            intakeCalories: intake,
            usedCalories: used,
            deficitSurplusCalories: used - intake
        )
        lastSnapshot = snapshot
        return snapshot
    }
}
