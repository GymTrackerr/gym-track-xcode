import Foundation
import SwiftData

@Model
final class MealRecipe {
    var id: UUID = UUID()
    var userId: UUID
    var name: String
    var batchSize: Double
    var servingUnitLabel: String?
    var defaultCategoryRaw: Int
    var cachedExtraNutrientsData: Data?
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \MealRecipeItem.mealRecipe)
    var items: [MealRecipeItem]

    init(
        userId: UUID,
        name: String,
        batchSize: Double = 1,
        servingUnitLabel: String? = nil,
        defaultCategory: FoodLogCategory = .other,
        cachedExtraNutrients: [String: Double]? = nil,
        isArchived: Bool = false
    ) {
        let timestamp = Date()
        self.userId = userId
        self.name = name
        self.batchSize = max(0.0001, batchSize)
        self.servingUnitLabel = servingUnitLabel
        self.defaultCategoryRaw = defaultCategory.rawValue
        self.cachedExtraNutrientsData = CodableJSONHelper.encode(cachedExtraNutrients)
        self.isArchived = isArchived
        self.createdAt = timestamp
        self.updatedAt = timestamp
        self.items = []
    }

    var defaultCategory: FoodLogCategory {
        get { FoodLogCategory(rawValue: defaultCategoryRaw) ?? .other }
        set { defaultCategoryRaw = newValue.rawValue }
    }

    var cachedExtraNutrients: [String: Double]? {
        get { CodableJSONHelper.decode(cachedExtraNutrientsData) }
        set { cachedExtraNutrientsData = CodableJSONHelper.encode(newValue) }
    }
}
