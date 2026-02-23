import Foundation
import SwiftData

@Model
final class Meal {
    var id: UUID = UUID()
    var userId: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \MealItem.meal)
    var items: [MealItem]

    @Relationship(inverse: \MealEntry.templateMeal)
    var entries: [MealEntry]

    init(userId: UUID, name: String) {
        self.userId = userId
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.items = []
        self.entries = []
    }
}
