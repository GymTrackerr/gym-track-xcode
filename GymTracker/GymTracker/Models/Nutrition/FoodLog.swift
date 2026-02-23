import Foundation
import SwiftData

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

@Model
final class FoodLog {
    var id: UUID = UUID()
    var userId: UUID
    var timestamp: Date
    var categoryRaw: Int
    var grams: Double
    var note: String?

    var food: Food
    var mealEntry: MealEntry?

    var category: FoodLogCategory {
        get { FoodLogCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var kcal: Double {
        grams * food.kcalPerGram
    }

    var protein: Double {
        grams * food.proteinPerGram
    }

    var carbs: Double {
        grams * food.carbPerGram
    }

    var fat: Double {
        grams * food.fatPerGram
    }

    init(
        userId: UUID,
        timestamp: Date,
        category: FoodLogCategory,
        grams: Double,
        note: String? = nil,
        food: Food,
        mealEntry: MealEntry? = nil
    ) {
        self.userId = userId
        self.timestamp = timestamp
        self.categoryRaw = category.rawValue
        self.grams = max(grams, 0)
        self.note = note
        self.food = food
        self.mealEntry = mealEntry
    }
}
