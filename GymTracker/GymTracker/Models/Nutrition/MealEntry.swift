import Foundation
import SwiftData

@Model
final class MealEntry {
    var id: UUID = UUID()
    var userId: UUID
    var timestamp: Date
    var categoryRaw: Int
    var note: String?

    var templateMeal: Meal?

    @Relationship(deleteRule: .cascade, inverse: \FoodLog.mealEntry)
    var logs: [FoodLog]

    var category: FoodLogCategory {
        get { FoodLogCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    init(
        userId: UUID,
        timestamp: Date,
        category: FoodLogCategory,
        note: String? = nil,
        templateMeal: Meal? = nil
    ) {
        self.userId = userId
        self.timestamp = timestamp
        self.categoryRaw = category.rawValue
        self.note = note
        self.templateMeal = templateMeal
        self.logs = []
    }
}
