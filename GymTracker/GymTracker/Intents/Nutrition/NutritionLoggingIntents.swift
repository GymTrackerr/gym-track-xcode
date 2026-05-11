import AppIntents
import Foundation

struct LogNutritionQuickAddIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Nutrition"
    static var description = IntentDescription("Quick add consumed nutrition values.")
    static var openAppWhenRun = false

    @Parameter(title: "Calories")
    var calories: Double?

    @Parameter(title: "Protein")
    var protein: Double?

    @Parameter(title: "Carbohydrates")
    var carbs: Double?

    @Parameter(title: "Fat")
    var fat: Double?

    @Parameter(title: "Fiber")
    var fiber: Double?

    @Parameter(title: "Sodium")
    var sodium: Double?

    @Parameter(title: "Total Sugars")
    var totalSugars: Double?

    @Parameter(title: "Custom Nutrient")
    var customNutrientName: String?

    @Parameter(title: "Custom Nutrient Amount")
    var customNutrientAmount: Double?

    @Parameter(title: "Category", default: .other)
    var category: NutritionIntentCategory

    @Parameter(title: "Note")
    var note: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try NutritionIntentStore.logQuickAdd(
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            fiber: fiber,
            sodium: sodium,
            totalSugars: totalSugars,
            customNutrientName: customNutrientName,
            customNutrientAmount: customNutrientAmount,
            category: category.foodLogCategory,
            note: note
        )
        return .result(dialog: "Logged \(result.summary).")
    }
}

struct LogFoodIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Food"
    static var description = IntentDescription("Log one of your saved foods.")
    static var openAppWhenRun = false

    @Parameter(title: "Food")
    var food: NutritionFoodEntity

    @Parameter(title: "Amount", default: 1)
    var amount: Double

    @Parameter(title: "Amount Type", default: .serving)
    var amountType: NutritionFoodAmountType

    @Parameter(title: "Category", default: .other)
    var category: NutritionIntentCategory

    @Parameter(title: "Note")
    var note: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try NutritionIntentStore.logFood(
            food: food,
            amount: amount,
            amountType: amountType,
            category: category.foodLogCategory,
            note: note
        )
        return .result(dialog: "Logged \(result.summary).")
    }
}

struct LogMealIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Meal"
    static var description = IntentDescription("Log one of your saved meals.")
    static var openAppWhenRun = false

    @Parameter(title: "Meal")
    var meal: NutritionMealEntity

    @Parameter(title: "Servings", default: 1)
    var servings: Double

    @Parameter(title: "Category", default: .other)
    var category: NutritionIntentCategory

    @Parameter(title: "Note")
    var note: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try NutritionIntentStore.logMeal(
            meal: meal,
            servings: servings,
            category: category.foodLogCategory,
            note: note
        )
        return .result(dialog: "Logged \(result.summary).")
    }
}

struct NutritionAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogNutritionQuickAddIntent(),
            phrases: [
                "Log nutrition in \(.applicationName)",
                "Quick add nutrition in \(.applicationName)",
                "Add calories to \(.applicationName)"
            ],
            shortTitle: "Log Nutrition",
            systemImageName: "fork.knife"
        )

        AppShortcut(
            intent: LogFoodIntent(),
            phrases: [
                "Log \(\.$food) in \(.applicationName)",
                "Add \(\.$food) to \(.applicationName)",
                "Log food in \(.applicationName)"
            ],
            shortTitle: "Log Food",
            systemImageName: "carrot"
        )

        AppShortcut(
            intent: LogMealIntent(),
            phrases: [
                "Log \(\.$meal) in \(.applicationName)",
                "Add \(\.$meal) to \(.applicationName)",
                "Log meal in \(.applicationName)"
            ],
            shortTitle: "Log Meal",
            systemImageName: "takeoutbag.and.cup.and.straw"
        )
    }
}
