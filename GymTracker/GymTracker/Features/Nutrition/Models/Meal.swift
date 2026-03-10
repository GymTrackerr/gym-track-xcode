import Foundation
import SwiftData

@Model
final class Meal {
    var id: UUID = UUID()
    var userId: UUID
    var name: String
    var defaultCategoryRaw: Int
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \MealItem.meal)
    var items: [MealItem]

    @Relationship(inverse: \MealEntry.templateMeal)
    var entries: [MealEntry]

    var defaultCategory: FoodLogCategory {
        get { FoodLogCategory(rawValue: defaultCategoryRaw) ?? .other }
        set { defaultCategoryRaw = newValue.rawValue }
    }

    init(userId: UUID, name: String, defaultCategory: FoodLogCategory = .other) {
        self.userId = userId
        self.name = name
        self.defaultCategoryRaw = defaultCategory.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
        self.items = []
        self.entries = []
    }
}
