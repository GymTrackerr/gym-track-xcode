import Foundation
import SwiftData

@Model
final class NutritionLogEntry {
    var id: UUID = UUID()
    var userId: UUID
    var timestamp: Date
    var logTypeRaw: Int
    var sourceItemId: UUID?
    var sourceMealId: UUID?
    var amount: Double
    var amountUnitSnapshot: String
    var categoryRaw: Int
    var note: String?
    var dayKey: String
    var logDate: Date
    var creationMethodRaw: Int
    var nameSnapshot: String
    var brandSnapshot: String?
    var servingUnitLabelSnapshot: String?
    var caloriesSnapshot: Double
    var proteinSnapshot: Double
    var carbsSnapshot: Double
    var fatSnapshot: Double
    var extraNutrientsSnapshotData: Data?
    var recipeItemsSnapshotData: Data?
    var createdAt: Date
    var updatedAt: Date

    init(
        userId: UUID,
        timestamp: Date,
        logType: NutritionLogType,
        sourceItemId: UUID?,
        sourceMealId: UUID?,
        amount: Double,
        amountUnitSnapshot: String,
        category: FoodLogCategory,
        note: String?,
        dayKey: String,
        logDate: Date,
        creationMethod: LogCreationMethod,
        nameSnapshot: String,
        brandSnapshot: String?,
        servingUnitLabelSnapshot: String?,
        caloriesSnapshot: Double,
        proteinSnapshot: Double,
        carbsSnapshot: Double,
        fatSnapshot: Double,
        extraNutrientsSnapshot: [String: Double]?,
        recipeItemsSnapshot: [RecipeItemSnapshot]?
    ) {
        let createdTimestamp = Date()
        self.userId = userId
        self.timestamp = timestamp
        self.logTypeRaw = logType.rawValue
        self.sourceItemId = sourceItemId
        self.sourceMealId = sourceMealId
        self.amount = max(0, amount)
        self.amountUnitSnapshot = amountUnitSnapshot
        self.categoryRaw = category.rawValue
        self.note = note
        self.dayKey = dayKey
        self.logDate = logDate
        self.creationMethodRaw = creationMethod.rawValue
        self.nameSnapshot = nameSnapshot
        self.brandSnapshot = brandSnapshot
        self.servingUnitLabelSnapshot = servingUnitLabelSnapshot
        self.caloriesSnapshot = max(0, caloriesSnapshot)
        self.proteinSnapshot = max(0, proteinSnapshot)
        self.carbsSnapshot = max(0, carbsSnapshot)
        self.fatSnapshot = max(0, fatSnapshot)
        self.extraNutrientsSnapshotData = CodableJSONHelper.encode(extraNutrientsSnapshot)
        self.recipeItemsSnapshotData = CodableJSONHelper.encode(recipeItemsSnapshot)
        self.createdAt = createdTimestamp
        self.updatedAt = createdTimestamp
    }

    var logType: NutritionLogType {
        get { NutritionLogType(rawValue: logTypeRaw) ?? .food }
        set { logTypeRaw = newValue.rawValue }
    }

    var category: FoodLogCategory {
        get { FoodLogCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var creationMethod: LogCreationMethod {
        get { LogCreationMethod(rawValue: creationMethodRaw) ?? .manual }
        set { creationMethodRaw = newValue.rawValue }
    }

    var extraNutrientsSnapshot: [String: Double]? {
        get { CodableJSONHelper.decode(extraNutrientsSnapshotData) }
        set { extraNutrientsSnapshotData = CodableJSONHelper.encode(newValue) }
    }

    var recipeItemsSnapshot: [RecipeItemSnapshot]? {
        get { CodableJSONHelper.decode(recipeItemsSnapshotData) }
        set { recipeItemsSnapshotData = CodableJSONHelper.encode(newValue) }
    }
}
