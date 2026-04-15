import Foundation
import SwiftData

@Model
final class NutritionTarget {
    var id: UUID = UUID()
    var userId: UUID?
    var soft_deleted: Bool = false
    var syncMetaId: UUID?
    var createdAt: Date
    var updatedAt: Date
    var calorieTarget: Double
    var proteinTarget: Double
    var carbTarget: Double
    var fatTarget: Double
    var isEnabled: Bool

    init(
        userId: UUID? = nil,
        calorieTarget: Double = 0,
        proteinTarget: Double = 0,
        carbTarget: Double = 0,
        fatTarget: Double = 0,
        isEnabled: Bool = false
    ) {
        let timestamp = Date()
        self.userId = userId
        self.soft_deleted = false
        self.syncMetaId = nil
        self.createdAt = timestamp
        self.updatedAt = timestamp
        self.calorieTarget = max(0, calorieTarget)
        self.proteinTarget = max(0, proteinTarget)
        self.carbTarget = max(0, carbTarget)
        self.fatTarget = max(0, fatTarget)
        self.isEnabled = isEnabled
    }
}

extension NutritionTarget: SyncTrackedRoot {
    static var syncModelType: SyncModelType { .nutritionTarget }
    var syncLinkedItemId: String { id.uuidString.lowercased() }
    var syncSeedDate: Date { createdAt }
}
