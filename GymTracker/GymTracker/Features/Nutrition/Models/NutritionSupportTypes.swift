import Foundation

enum FoodItemKind: Int, Codable, CaseIterable, Identifiable {
    case food = 0
    case drink = 1
    case ingredient = 2

    var id: Int { rawValue }
}

enum FoodLogCategory: Int, CaseIterable, Identifiable {
    case breakfast = 0
    case lunch = 1
    case dinner = 2
    case snack = 3
    case other = 4

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        case .snack: return "Snack"
        case .other: return "Other"
        }
    }

    static let displayOrder: [FoodLogCategory] = [.breakfast, .lunch, .dinner, .snack, .other]
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
    case importedBackup = 4

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
