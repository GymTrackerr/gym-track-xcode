import Foundation
import SwiftData

@Model
final class MealItem {
    var id: UUID = UUID()
    var order: Int
    var grams: Double

    var meal: Meal?
    var food: Food

    init(order: Int, grams: Double, meal: Meal? = nil, food: Food) {
        self.order = order
        self.grams = max(grams, 0)
        self.meal = meal
        self.food = food
    }
}
