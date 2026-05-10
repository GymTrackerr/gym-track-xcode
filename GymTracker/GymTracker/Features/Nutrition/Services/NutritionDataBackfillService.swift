import Foundation
import SwiftData

@MainActor
final class NutritionDataBackfillService {
    private let modelContext: ModelContext

    init(context: ModelContext) {
        self.modelContext = context
    }

    func backfill(userId: UUID) throws {
        var changed = false
        changed = try backfillFoods(userId: userId) || changed
        changed = try backfillLogs(userId: userId) || changed
        changed = try backfillTargets(userId: userId) || changed
        changed = try seedNutrientDefinitions(userId: userId) || changed

        if changed {
            try modelContext.save()
        }
    }

    private func backfillFoods(userId: UUID) throws -> Bool {
        let descriptor = FetchDescriptor<FoodItem>(
            predicate: #Predicate<FoodItem> { item in
                item.userId == userId
            }
        )
        let foods = try modelContext.fetch(descriptor)
        var changed = false

        for food in foods {
            if food.providedNutrientKeysData == nil {
                food.providedNutrientKeys = NutritionNutrientKey.coreKeySet
                changed = true
            }

            if food.servingQuantity == nil,
               let referenceLabel = food.referenceLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
               !referenceLabel.isEmpty {
                food.servingQuantity = food.referenceQuantity
                food.servingUnitLabel = referenceLabel
                changed = true
            }
        }

        return changed
    }

    private func backfillLogs(userId: UUID) throws -> Bool {
        let descriptor = FetchDescriptor<NutritionLogEntry>(
            predicate: #Predicate<NutritionLogEntry> { log in
                log.userId == userId
            }
        )
        let logs = try modelContext.fetch(descriptor)
        var changed = false

        for log in logs {
            if log.providedNutrientKeysData == nil {
                switch log.logType {
                case .quickCalories:
                    log.providedNutrientKeys = [NutritionNutrientKey.calories]
                case .food, .meal:
                    log.providedNutrientKeys = NutritionNutrientKey.coreKeySet
                }
                changed = true
            }

            if log.amountModeRaw == nil {
                switch log.logType {
                case .food:
                    log.amountMode = .baseUnit
                case .meal:
                    log.amountMode = .serving
                    if log.servingCountSnapshot == nil {
                        log.servingCountSnapshot = log.amount
                    }
                case .quickCalories:
                    log.amountMode = .quickAdd
                }
                changed = true
            }
        }

        return changed
    }

    private func backfillTargets(userId: UUID) throws -> Bool {
        let descriptor = FetchDescriptor<NutritionTarget>(
            predicate: #Predicate<NutritionTarget> { target in
                target.userId == userId || target.userId == nil
            }
        )
        let targets = try modelContext.fetch(descriptor)
        var changed = false

        for target in targets where target.labelProfileRaw == nil {
            target.labelProfile = .hybrid
            changed = true
        }

        return changed
    }

    private func seedNutrientDefinitions(userId: UUID) throws -> Bool {
        let descriptor = FetchDescriptor<NutritionNutrientDefinition>(
            predicate: #Predicate<NutritionNutrientDefinition> { definition in
                definition.userId == userId
            }
        )
        let existing = try modelContext.fetch(descriptor)
        let existingKeys = Set(existing.map { NutritionNutrientKey.normalized($0.key) })
        var changed = false

        for preset in NutritionNutrientPreset.defaultPresets {
            let key = NutritionNutrientKey.normalized(preset.key)
            guard !existingKeys.contains(key) else { continue }

            let definition = NutritionNutrientDefinition(
                userId: userId,
                key: key,
                displayName: preset.displayName,
                unitLabel: preset.unitLabel,
                group: preset.group,
                sortOrder: preset.sortOrder,
                dailyGoal: nil,
                isVisible: true,
                isArchived: false
            )
            modelContext.insert(definition)
            try SyncRootMetadataManager.markCreated(definition, in: modelContext)
            changed = true
        }

        return changed
    }
}
