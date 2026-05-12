import AppIntents
import Foundation

enum NutritionIntentCategory: String, AppEnum, CaseIterable {
    case breakfast
    case lunch
    case dinner
    case snack
    case other

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource(
        "nutrition.intent.category.type",
        defaultValue: "Nutrition Category",
        table: "Nutrition",
        comment: "Type name for the nutrition category App Intent enum."
    ))
    static var caseDisplayRepresentations: [NutritionIntentCategory: DisplayRepresentation] = [
        .breakfast: DisplayRepresentation(title: LocalizedStringResource(
            "nutrition.intent.category.breakfast",
            defaultValue: "Breakfast",
            table: "Nutrition",
            comment: "Breakfast nutrition category."
        )),
        .lunch: DisplayRepresentation(title: LocalizedStringResource(
            "nutrition.intent.category.lunch",
            defaultValue: "Lunch",
            table: "Nutrition",
            comment: "Lunch nutrition category."
        )),
        .dinner: DisplayRepresentation(title: LocalizedStringResource(
            "nutrition.intent.category.dinner",
            defaultValue: "Dinner",
            table: "Nutrition",
            comment: "Dinner nutrition category."
        )),
        .snack: DisplayRepresentation(title: LocalizedStringResource(
            "nutrition.intent.category.snack",
            defaultValue: "Snack",
            table: "Nutrition",
            comment: "Snack nutrition category."
        )),
        .other: DisplayRepresentation(title: LocalizedStringResource(
            "nutrition.intent.category.other",
            defaultValue: "Other",
            table: "Nutrition",
            comment: "Other nutrition category."
        ))
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

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource(
        "nutrition.intent.amountType.type",
        defaultValue: "Food Amount Type",
        table: "Nutrition",
        comment: "Type name for the food amount App Intent enum."
    ))
    static var caseDisplayRepresentations: [NutritionFoodAmountType: DisplayRepresentation] = [
        .serving: DisplayRepresentation(title: LocalizedStringResource(
            "nutrition.intent.amountType.serving",
            defaultValue: "Serving",
            table: "Nutrition",
            comment: "Serving food amount type."
        )),
        .foodUnit: DisplayRepresentation(title: LocalizedStringResource(
            "nutrition.intent.amountType.foodUnit",
            defaultValue: "Food Unit",
            table: "Nutrition",
            comment: "Food unit amount type."
        ))
    ]
}
