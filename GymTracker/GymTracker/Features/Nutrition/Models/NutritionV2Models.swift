import Foundation
import SwiftData

enum FoodItemKind: Int, Codable, CaseIterable, Identifiable {
    case food = 0
    case drink = 1
    case ingredient = 2

    var id: Int { rawValue }
}

enum FoodItemUnit: Int, Codable, CaseIterable, Identifiable {
    case grams = 0
    case milliliters = 1
    case piece = 2

    var id: Int { rawValue }

    var shortLabel: String {
        switch self {
        case .grams:
            return "g"
        case .milliliters:
            return "ml"
        case .piece:
            return "pc"
        }
    }

    var displayName: String {
        switch self {
        case .grams:
            return "Grams"
        case .milliliters:
            return "Milliliters"
        case .piece:
            return "Piece"
        }
    }
}

enum NutritionLogType: Int, Codable, CaseIterable, Identifiable {
    case food = 0
    case meal = 1
    case quickCalories = 2

    var id: Int { rawValue }
}

enum LogCreationMethod: Int, Codable, CaseIterable, Identifiable {
    case manual = 0
    case foodItem = 1
    case mealRecipe = 2
    case quickEntry = 3
    case migratedV1 = 4
    case importedBackup = 5

    var id: Int { rawValue }
}

struct NutritionFacts: Codable, Hashable {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var extraNutrients: [String: Double]?

    static let zero = NutritionFacts(calories: 0, protein: 0, carbs: 0, fat: 0, extraNutrients: nil)
}

struct RecipeItemSnapshot: Codable, Hashable {
    var name: String
    var amount: Double
    var amountUnit: String
    var caloriesSnapshot: Double
    var proteinSnapshot: Double
    var carbsSnapshot: Double
    var fatSnapshot: Double
    var extraNutrientsSnapshot: [String: Double]?
}

// MARK: - Shared JSON Encoding/Decoding Utility

enum CodableJSONHelper {
    static func encode<T: Encodable>(_ value: T?) -> Data? {
        guard let value else { return nil }
        return try? JSONEncoder().encode(value)
    }

    static func decode<T: Decodable>(_ data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

struct NutritionLogDraft {
    var logType: NutritionLogType
    var creationMethod: LogCreationMethod
    var sourceItemId: UUID?
    var sourceMealId: UUID?
    var nameSnapshot: String
    var brandSnapshot: String?
    var amount: Double
    var amountUnitSnapshot: String
    var servingUnitLabelSnapshot: String?
    var caloriesSnapshot: Double
    var proteinSnapshot: Double
    var carbsSnapshot: Double
    var fatSnapshot: Double
    var extraNutrientsSnapshot: [String: Double]?
    var recipeItemsSnapshot: [RecipeItemSnapshot]?
    var timestamp: Date
    var category: FoodLogCategory
    var note: String?
}

@Model
final class FoodItem {
    var id: UUID = UUID()
    var userId: UUID
    var name: String
    var brand: String?
    var referenceLabel: String?
    var referenceQuantity: Double
    var caloriesPerReference: Double
    var proteinPerReference: Double
    var carbsPerReference: Double
    var fatPerReference: Double
    var extraNutrientsData: Data?
    var isArchived: Bool
    var isFavorite: Bool
    var kindRaw: Int
    var unitRaw: Int
    var createdAt: Date
    var updatedAt: Date

    @Relationship(inverse: \MealRecipeItem.foodItem)
    var recipeItems: [MealRecipeItem]

    init(
        userId: UUID,
        name: String,
        brand: String? = nil,
        referenceLabel: String? = nil,
        referenceQuantity: Double,
        caloriesPerReference: Double,
        proteinPerReference: Double,
        carbsPerReference: Double,
        fatPerReference: Double,
        extraNutrients: [String: Double]? = nil,
        isArchived: Bool = false,
        isFavorite: Bool = false,
        kind: FoodItemKind = .food,
        unit: FoodItemUnit = .grams
    ) {
        self.userId = userId
        self.name = name
        self.brand = brand
        self.referenceLabel = referenceLabel
        self.referenceQuantity = max(0.0001, referenceQuantity)
        self.caloriesPerReference = max(0, caloriesPerReference)
        self.proteinPerReference = max(0, proteinPerReference)
        self.carbsPerReference = max(0, carbsPerReference)
        self.fatPerReference = max(0, fatPerReference)
        self.extraNutrientsData = CodableJSONHelper.encode(extraNutrients)
        self.isArchived = isArchived
        self.isFavorite = isFavorite
        self.kindRaw = kind.rawValue
        self.unitRaw = unit.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
        self.recipeItems = []
    }

    var kind: FoodItemKind {
        get { FoodItemKind(rawValue: kindRaw) ?? .food }
        set { kindRaw = newValue.rawValue }
    }

    var unit: FoodItemUnit {
        get { FoodItemUnit(rawValue: unitRaw) ?? .grams }
        set { unitRaw = newValue.rawValue }
    }

    var extraNutrients: [String: Double]? {
        get { CodableJSONHelper.decode(extraNutrientsData) }
        set { extraNutrientsData = CodableJSONHelper.encode(newValue) }
    }

    var caloriesPerUnit: Double {
        guard referenceQuantity > 0 else { return 0 }
        return caloriesPerReference / referenceQuantity
    }

    var proteinPerUnit: Double {
        guard referenceQuantity > 0 else { return 0 }
        return proteinPerReference / referenceQuantity
    }

    var carbsPerUnit: Double {
        guard referenceQuantity > 0 else { return 0 }
        return carbsPerReference / referenceQuantity
    }

    var fatPerUnit: Double {
        guard referenceQuantity > 0 else { return 0 }
        return fatPerReference / referenceQuantity
    }
}

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
        self.userId = userId
        self.name = name
        self.batchSize = max(0.0001, batchSize)
        self.servingUnitLabel = servingUnitLabel
        self.defaultCategoryRaw = defaultCategory.rawValue
        self.cachedExtraNutrientsData = CodableJSONHelper.encode(cachedExtraNutrients)
        self.isArchived = isArchived
        self.createdAt = Date()
        self.updatedAt = Date()
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
        self.createdAt = Date()
        self.updatedAt = Date()
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
