import AppIntents
import Foundation

enum NutritionIntentCategory: String, AppEnum, CaseIterable {
    case breakfast
    case lunch
    case dinner
    case snack
    case other

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Nutrition Category")
    static var caseDisplayRepresentations: [NutritionIntentCategory: DisplayRepresentation] = [
        .breakfast: "Breakfast",
        .lunch: "Lunch",
        .dinner: "Dinner",
        .snack: "Snack",
        .other: "Other"
    ]

    var foodLogCategory: FoodLogCategory {
        switch self {
        case .breakfast:
            return .breakfast
        case .lunch:
            return .lunch
        case .dinner:
            return .dinner
        case .snack:
            return .snack
        case .other:
            return .other
        }
    }
}

enum NutritionFoodAmountType: String, AppEnum, CaseIterable {
    case serving
    case foodUnit

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Food Amount Type")
    static var caseDisplayRepresentations: [NutritionFoodAmountType: DisplayRepresentation] = [
        .serving: "Serving",
        .foodUnit: "Food Unit"
    ]
}
