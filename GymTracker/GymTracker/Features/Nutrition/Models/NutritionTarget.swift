import Foundation
import SwiftData

@Model
final class NutritionTarget {
    var id: UUID = UUID()
    var createdAt: Date
    var updatedAt: Date
    var calorieTarget: Double
    var proteinTarget: Double
    var carbTarget: Double
    var fatTarget: Double
    var isEnabled: Bool

    init(
        calorieTarget: Double = 0,
        proteinTarget: Double = 0,
        carbTarget: Double = 0,
        fatTarget: Double = 0,
        isEnabled: Bool = false
    ) {
        self.createdAt = Date()
        self.updatedAt = Date()
        self.calorieTarget = max(0, calorieTarget)
        self.proteinTarget = max(0, proteinTarget)
        self.carbTarget = max(0, carbTarget)
        self.fatTarget = max(0, fatTarget)
        self.isEnabled = isEnabled
    }
}
