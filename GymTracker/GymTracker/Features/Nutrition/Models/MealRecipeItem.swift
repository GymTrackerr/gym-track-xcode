import Foundation
import SwiftData

@Model
final class MealRecipeItem {
    var id: UUID = UUID()
    var amount: Double
    var amountUnitRaw: Int
    var order: Int

    var mealRecipe: MealRecipe?
    var foodItem: FoodItem

    init(
        amount: Double,
        amountUnit: FoodItemUnit,
        order: Int,
        mealRecipe: MealRecipe? = nil,
        foodItem: FoodItem
    ) {
        self.amount = max(0, amount)
        self.amountUnitRaw = amountUnit.rawValue
        self.order = order
        self.mealRecipe = mealRecipe
        self.foodItem = foodItem
    }

    var amountUnit: FoodItemUnit {
        get { FoodItemUnit(rawValue: amountUnitRaw) ?? .grams }
        set { amountUnitRaw = newValue.rawValue }
    }
}
