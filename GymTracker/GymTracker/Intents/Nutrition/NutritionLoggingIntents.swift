import AppIntents
import Foundation

struct LogNutritionQuickAddIntent: AppIntent {
    static var title = LocalizedStringResource(
        "nutrition.intent.quickAdd.title",
        defaultValue: "Create Log",
        table: "Nutrition",
        comment: "Title for the App Intent that quickly logs nutrition values."
    )
    static var description = IntentDescription(LocalizedStringResource(
        "nutrition.intent.quickAdd.description",
        defaultValue: "Quick add consumed nutrition values.",
        table: "Nutrition",
        comment: "Description for the App Intent that quickly logs nutrition values."
    ))
    static var supportedModes: IntentModes { .background }

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
    static var title = LocalizedStringResource(
        "nutrition.intent.logFood.title",
        defaultValue: "Log Food",
        table: "Nutrition",
        comment: "Title for the App Intent that logs a saved food."
    )
    static var description = IntentDescription(LocalizedStringResource(
        "nutrition.intent.logFood.description",
        defaultValue: "Log one of your saved foods.",
        table: "Nutrition",
        comment: "Description for the App Intent that logs a saved food."
    ))
    static var supportedModes: IntentModes { .background }

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
    static var title = LocalizedStringResource(
        "nutrition.intent.logMeal.title",
        defaultValue: "Log Meal",
        table: "Nutrition",
        comment: "Title for the App Intent that logs a saved meal."
    )
    static var description = IntentDescription(LocalizedStringResource(
        "nutrition.intent.logMeal.description",
        defaultValue: "Log one of your saved meals.",
        table: "Nutrition",
        comment: "Description for the App Intent that logs a saved meal."
    ))
    static var supportedModes: IntentModes { .background }

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

struct GymTrackerAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogNutritionQuickAddIntent(),
            phrases: [
                "Create nutrition log in \(.applicationName)",
                "Log nutrition in \(.applicationName)",
                "Quick add nutrition in \(.applicationName)",
                "Add calories to \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource(
                "nutrition.shortcut.quickAdd.title",
                defaultValue: "Create Log",
                table: "Nutrition",
                comment: "Short title for the quick nutrition logging shortcut."
            ),
            systemImageName: "fork.knife"
        )

        AppShortcut(
            intent: LogFoodIntent(),
            phrases: [
                "Log \(\.$food) in \(.applicationName)",
                "Add \(\.$food) to \(.applicationName)",
                "Log food in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource(
                "nutrition.shortcut.logFood.title",
                defaultValue: "Log Food",
                table: "Nutrition",
                comment: "Short title for the saved food logging shortcut."
            ),
            systemImageName: "carrot"
        )

        AppShortcut(
            intent: LogMealIntent(),
            phrases: [
                "Log \(\.$meal) in \(.applicationName)",
                "Add \(\.$meal) to \(.applicationName)",
                "Log meal in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource(
                "nutrition.shortcut.logMeal.title",
                defaultValue: "Log Meal",
                table: "Nutrition",
                comment: "Short title for the saved meal logging shortcut."
            ),
            systemImageName: "takeoutbag.and.cup.and.straw"
        )

        AppShortcut(
            intent: StartSessionIntent(),
            phrases: [
                "Start a session in \(.applicationName)",
                "Start \(\.$sessionType) session in \(.applicationName)",
                "Start session from \(\.$routine) in \(.applicationName)",
                "Start programme session from \(\.$programme) in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource(
                "sessions.shortcut.startSession.title",
                defaultValue: "Start Session",
                table: "Sessions",
                comment: "Short title for the start session shortcut."
            ),
            systemImageName: "figure.strengthtraining.traditional"
        )
    }
}
