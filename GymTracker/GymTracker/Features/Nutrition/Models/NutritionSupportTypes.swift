import Foundation

enum FoodItemKind: Int, Codable, CaseIterable, Identifiable {
    case food = 0
    case drink = 1
    case ingredient = 2

    var id: Int { rawValue }

    var displayNameResource: LocalizedStringResource {
        switch self {
        case .food:
            return LocalizedStringResource("nutrition.foodKind.food", defaultValue: "Food", table: "Nutrition")
        case .drink:
            return LocalizedStringResource("nutrition.foodKind.drink", defaultValue: "Drink", table: "Nutrition")
        case .ingredient:
            return LocalizedStringResource("nutrition.foodKind.ingredient", defaultValue: "Ingredient", table: "Nutrition")
        }
    }
}

enum FoodLogCategory: Int, CaseIterable, Identifiable {
    case breakfast = 0
    case lunch = 1
    case dinner = 2
    case snack = 3
    case other = 4

    var id: Int { rawValue }

    var displayName: String {
        String(localized: displayNameResource)
    }

    var displayNameResource: LocalizedStringResource {
        switch self {
        case .breakfast:
            return LocalizedStringResource("nutrition.category.breakfast", defaultValue: "Breakfast", table: "Nutrition")
        case .lunch:
            return LocalizedStringResource("nutrition.category.lunch", defaultValue: "Lunch", table: "Nutrition")
        case .dinner:
            return LocalizedStringResource("nutrition.category.dinner", defaultValue: "Dinner", table: "Nutrition")
        case .snack:
            return LocalizedStringResource("nutrition.category.snack", defaultValue: "Snack", table: "Nutrition")
        case .other:
            return LocalizedStringResource("nutrition.category.other", defaultValue: "Other", table: "Nutrition")
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
        String(localized: displayNameResource)
    }

    var displayNameResource: LocalizedStringResource {
        switch self {
        case .grams:
            return LocalizedStringResource("nutrition.unit.grams", defaultValue: "Grams", table: "Nutrition")
        case .milliliters:
            return LocalizedStringResource("nutrition.unit.milliliters", defaultValue: "Milliliters", table: "Nutrition")
        case .piece:
            return LocalizedStringResource("nutrition.unit.piece", defaultValue: "Piece", table: "Nutrition")
        }
    }
}

enum NutritionLabelProfile: String, Codable, CaseIterable, Identifiable {
    case defaultProfile = "default"
    case ukEU
    case us

    var id: String { rawValue }

    var displayName: String {
        String(localized: displayNameResource)
    }

    var displayNameResource: LocalizedStringResource {
        switch self {
        case .defaultProfile:
            return LocalizedStringResource("nutrition.labelProfile.default", defaultValue: "Default", table: "Nutrition")
        case .ukEU:
            return LocalizedStringResource("nutrition.labelProfile.ukEU", defaultValue: "UK/EU", table: "Nutrition")
        case .us:
            return LocalizedStringResource("nutrition.labelProfile.us", defaultValue: "US", table: "Nutrition")
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Self.storedValue(rawValue) ?? .defaultProfile
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static func storedValue(_ rawValue: String?) -> NutritionLabelProfile? {
        guard let rawValue else { return nil }
        switch rawValue {
        case "hybrid":
            return .defaultProfile
        default:
            return NutritionLabelProfile(rawValue: rawValue)
        }
    }
}

enum NutritionLogType: Int, Codable, CaseIterable, Identifiable {
    case food = 0
    case meal = 1
    case quickCalories = 2

    var id: Int { rawValue }
}

enum NutritionLogAmountMode: Int, Codable, CaseIterable, Identifiable {
    case baseUnit = 0
    case serving = 1
    case quickAdd = 2

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

enum NutritionNutrientKey {
    static let calories = "calories"
    static let protein = "protein"
    static let carbs = "carbs"
    static let fat = "fat"

    static let coreKeys: [String] = [calories, protein, carbs, fat]
    static let coreKeySet = Set(coreKeys)

    static func normalized(_ value: String) -> String {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let pieces = trimmed.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "-"
        }

        return pieces.joined()
            .split(separator: "-")
            .joined(separator: "-")
    }
}

enum NutritionNutrientGroup: String, Codable, CaseIterable, Identifiable {
    case fat
    case carbohydrate
    case mineral
    case vitamin
    case energy
    case other

    var id: String { rawValue }

    var displayName: String {
        String(localized: displayNameResource)
    }

    var displayNameResource: LocalizedStringResource {
        switch self {
        case .fat:
            return LocalizedStringResource("nutrition.nutrientGroup.fat", defaultValue: "Fat", table: "Nutrition")
        case .carbohydrate:
            return LocalizedStringResource("nutrition.nutrientGroup.carbohydrate", defaultValue: "Carbohydrate", table: "Nutrition")
        case .mineral:
            return LocalizedStringResource("nutrition.nutrientGroup.mineral", defaultValue: "Mineral", table: "Nutrition")
        case .vitamin:
            return LocalizedStringResource("nutrition.nutrientGroup.vitamin", defaultValue: "Vitamin", table: "Nutrition")
        case .energy:
            return LocalizedStringResource("nutrition.nutrientGroup.energy", defaultValue: "Energy", table: "Nutrition")
        case .other:
            return LocalizedStringResource("nutrition.nutrientGroup.other", defaultValue: "Other", table: "Nutrition")
        }
    }
}

struct NutritionNutrientPreset: Decodable, Hashable {
    let key: String
    let displayName: String
    let unitLabel: String
    let group: NutritionNutrientGroup
    let sortOrder: Int

    static func defaultPresets() -> [NutritionNutrientPreset] {
        NutritionNutrientPresetLoader.loadDefaultPresets()
    }
}

private enum NutritionNutrientPresetLoader {
    static func loadDefaultPresets() -> [NutritionNutrientPreset] {
        let candidateURLs: [URL?] = [
            Bundle.main.url(
                forResource: "nutrition_nutrient_presets",
                withExtension: "json",
                subdirectory: "Features/Nutrition"
            ),
            Bundle.main.url(forResource: "nutrition_nutrient_presets", withExtension: "json")
        ]

        guard let url = candidateURLs.compactMap({ $0 }).first else {
            print("Missing bundled nutrition nutrient presets JSON.")
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([NutritionNutrientPreset].self, from: data)
        } catch {
            print("Failed to load bundled nutrition nutrient presets: \(error)")
            return []
        }
    }
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
    var amountMode: NutritionLogAmountMode
    var servingQuantitySnapshot: Double?
    var servingCountSnapshot: Double?
    var caloriesSnapshot: Double
    var proteinSnapshot: Double
    var carbsSnapshot: Double
    var fatSnapshot: Double
    var extraNutrientsSnapshot: [String: Double]?
    var recipeItemsSnapshot: [RecipeItemSnapshot]?
    var providedNutrientKeys: Set<String>
    var timestamp: Date
    var category: FoodLogCategory
    var note: String?
}
