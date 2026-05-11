import Foundation
import SwiftData

@Model
final class NutritionNutrientDefinition {
    var id: UUID = UUID()
    var userId: UUID
    var key: String
    var displayName: String
    var unitLabel: String
    var groupRaw: String?
    var sortOrder: Int
    var dailyGoal: Double?
    var isVisible: Bool
    var isArchived: Bool
    var soft_deleted: Bool = false
    var syncMetaId: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        userId: UUID,
        key: String,
        displayName: String,
        unitLabel: String,
        group: NutritionNutrientGroup? = nil,
        sortOrder: Int,
        dailyGoal: Double? = nil,
        isVisible: Bool = true,
        isArchived: Bool = false
    ) {
        let timestamp = Date()
        self.userId = userId
        self.key = NutritionNutrientKey.normalized(key)
        self.displayName = displayName
        self.unitLabel = unitLabel
        self.groupRaw = group?.rawValue
        self.sortOrder = sortOrder
        self.dailyGoal = dailyGoal.map { max(0, $0) }
        self.isVisible = isVisible
        self.isArchived = isArchived
        self.soft_deleted = isArchived
        self.syncMetaId = nil
        self.createdAt = timestamp
        self.updatedAt = timestamp
    }

    var group: NutritionNutrientGroup? {
        get {
            guard let groupRaw else { return nil }
            return NutritionNutrientGroup(rawValue: groupRaw)
        }
        set { groupRaw = newValue?.rawValue }
    }
}

extension NutritionNutrientDefinition: SyncTrackedRoot {
    static var syncModelType: SyncModelType { .nutritionNutrientDefinition }
    var syncLinkedItemId: String { id.uuidString.lowercased() }
    var syncSeedDate: Date { createdAt }
    var legacyDeleteBridgeValue: Bool? { isArchived }

    func applyLegacyDeleteBridge(_ value: Bool) {
        isArchived = value
    }
}
