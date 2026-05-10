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
    var labelProfileRaw: String?

    init(
        userId: UUID? = nil,
        calorieTarget: Double = 0,
        proteinTarget: Double = 0,
        carbTarget: Double = 0,
        fatTarget: Double = 0,
        isEnabled: Bool = false,
        labelProfile: NutritionLabelProfile = .hybrid
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
        self.labelProfileRaw = labelProfile.rawValue
    }

    var labelProfile: NutritionLabelProfile {
        get {
            guard let labelProfileRaw else { return .hybrid }
            return NutritionLabelProfile(rawValue: labelProfileRaw) ?? .hybrid
        }
        set { labelProfileRaw = newValue.rawValue }
    }
}

extension NutritionTarget: SyncTrackedRoot {
    static var syncModelType: SyncModelType { .nutritionTarget }
    var syncLinkedItemId: String { id.uuidString.lowercased() }
    var syncSeedDate: Date { createdAt }
}
