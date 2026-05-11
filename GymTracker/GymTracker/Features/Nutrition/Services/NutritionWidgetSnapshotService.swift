import Foundation
import SwiftData
import WidgetKit

final class NutritionWidgetSnapshotService {
    private let context: ModelContext
    private let calendar: Calendar

    init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    @discardableResult
    func refresh(for user: User, date: Date = Date(), reloadTimelines: Bool = true) throws -> NutritionWidgetSnapshot {
        let snapshot = try buildSnapshot(for: user, date: date)
        try NutritionWidgetSnapshotStore.save(snapshot)
        if reloadTimelines {
            WidgetCenter.shared.reloadTimelines(ofKind: NutritionWidgetSnapshotStore.widgetKind)
        }
        return snapshot
    }

    func clear(reloadTimelines: Bool = true) {
        NutritionWidgetSnapshotStore.clear()
        if reloadTimelines {
            WidgetCenter.shared.reloadTimelines(ofKind: NutritionWidgetSnapshotStore.widgetKind)
        }
    }

    private func buildSnapshot(for user: User, date: Date) throws -> NutritionWidgetSnapshot {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        let dayKey = Self.dayKey(for: dayStart, calendar: calendar)
        let logs = try fetchLogs(userId: user.id, start: dayStart, end: dayEnd)
        let target = try fetchTarget(userId: user.id)
        let health = try fetchHealthSummary(userId: user.id.uuidString, dayKey: dayKey)
        let definitions = try fetchVisibleNutrientDefinitions(userId: user.id)

        let eatenCalories = total(logs, key: NutritionNutrientKey.calories) { $0.caloriesSnapshot }
        let protein = total(logs, key: NutritionNutrientKey.protein) { $0.proteinSnapshot }
        let carbs = total(logs, key: NutritionNutrientKey.carbs) { $0.carbsSnapshot }
        let fat = total(logs, key: NutritionNutrientKey.fat) { $0.fatSnapshot }
        let goals = goalSnapshots(from: definitions, logs: logs)

        return NutritionWidgetSnapshot(
            dayKey: dayKey,
            date: dayStart,
            eatenCalories: eatenCalories,
            calorieTarget: targetValue(target?.calorieTarget, enabled: target?.isEnabled == true),
            protein: protein,
            proteinTarget: targetValue(target?.proteinTarget, enabled: target?.isEnabled == true),
            carbs: carbs,
            carbsTarget: targetValue(target?.carbTarget, enabled: target?.isEnabled == true),
            fat: fat,
            fatTarget: targetValue(target?.fatTarget, enabled: target?.isEnabled == true),
            activeBurnedCalories: health?.activeEnergyKcal,
            restingBurnedCalories: health?.restingEnergyKcal,
            goalSnapshots: goals,
            hasNutritionData: !logs.isEmpty,
            updatedAt: Date()
        )
    }

    private func fetchLogs(userId: UUID, start: Date, end: Date) throws -> [NutritionLogEntry] {
        let descriptor = FetchDescriptor<NutritionLogEntry>(
            predicate: #Predicate<NutritionLogEntry> { log in
                log.userId == userId && log.soft_deleted == false && log.timestamp >= start && log.timestamp < end
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return try context.fetch(descriptor)
    }

    private func fetchTarget(userId: UUID) throws -> NutritionTarget? {
        let descriptor = FetchDescriptor<NutritionTarget>(
            predicate: #Predicate<NutritionTarget> { target in
                target.soft_deleted == false
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let targets = try context.fetch(descriptor)
        return targets.first { $0.userId == userId } ?? targets.first { $0.userId == nil }
    }

    private func fetchHealthSummary(userId: String, dayKey: String) throws -> HealthKitDailyAggregateData? {
        let cacheKey = "\(userId)|\(dayKey)"
        let descriptor = FetchDescriptor<HealthKitDailyAggregateData>(
            predicate: #Predicate<HealthKitDailyAggregateData> { summary in
                summary.cacheKey == cacheKey && summary.soft_deleted == false
            }
        )
        return try context.fetch(descriptor).first
    }

    private func fetchVisibleNutrientDefinitions(userId: UUID) throws -> [NutritionNutrientDefinition] {
        let descriptor = FetchDescriptor<NutritionNutrientDefinition>(
            predicate: #Predicate<NutritionNutrientDefinition> { definition in
                definition.userId == userId &&
                    definition.soft_deleted == false &&
                    definition.isArchived == false &&
                    definition.isVisible == true
            },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.displayName)]
        )
        return try context.fetch(descriptor)
    }

    private func goalSnapshots(
        from definitions: [NutritionNutrientDefinition],
        logs: [NutritionLogEntry]
    ) -> [NutritionWidgetGoalSnapshot] {
        definitions.compactMap { definition in
            guard let goal = definition.dailyGoal, goal > 0 else { return nil }
            let key = NutritionNutrientKey.normalized(definition.key)
            guard !key.isEmpty else { return nil }
            let value = logs.reduce(0) { partial, log in
                partial + (log.hasProvidedNutrient(key) ? (log.extraNutrientsSnapshot?[key] ?? 0) : 0)
            }
            return NutritionWidgetGoalSnapshot(
                key: key,
                name: definition.displayName,
                value: value,
                target: goal,
                unit: definition.unitLabel
            )
        }
        .prefix(3)
        .map { $0 }
    }

    private func total(
        _ logs: [NutritionLogEntry],
        key: String,
        value: (NutritionLogEntry) -> Double
    ) -> Double {
        logs.reduce(0) { partial, log in
            partial + (log.hasProvidedNutrient(key) ? value(log) : 0)
        }
    }

    private func targetValue(_ value: Double?, enabled: Bool) -> Double? {
        guard enabled, let value, value > 0 else { return nil }
        return value
    }

    private static func dayKey(for date: Date, calendar sourceCalendar: Calendar) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = sourceCalendar.timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
    }
}
