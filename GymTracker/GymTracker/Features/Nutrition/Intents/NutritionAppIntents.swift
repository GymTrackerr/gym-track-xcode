import AppIntents
import Foundation
import SwiftData
import WidgetKit

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

struct NutritionFoodEntity: AppEntity {
    static let defaultQuery = NutritionFoodEntityQuery()
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Food")

    var id: UUID
    var name: String
    var subtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(subtitle)")
    }
}

struct NutritionFoodEntityQuery: EntityStringQuery {
    func entities(for identifiers: [NutritionFoodEntity.ID]) async throws -> [NutritionFoodEntity] {
        try await MainActor.run {
            try NutritionIntentStore.foodEntities(identifiers: identifiers)
        }
    }

    func entities(matching string: String) async throws -> [NutritionFoodEntity] {
        try await MainActor.run {
            try NutritionIntentStore.foodEntities(matching: string)
        }
    }

    func suggestedEntities() async throws -> [NutritionFoodEntity] {
        try await MainActor.run {
            try NutritionIntentStore.suggestedFoodEntities()
        }
    }
}

struct NutritionMealEntity: AppEntity {
    static let defaultQuery = NutritionMealEntityQuery()
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Meal")

    var id: UUID
    var name: String
    var subtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(subtitle)")
    }
}

struct NutritionMealEntityQuery: EntityStringQuery {
    func entities(for identifiers: [NutritionMealEntity.ID]) async throws -> [NutritionMealEntity] {
        try await MainActor.run {
            try NutritionIntentStore.mealEntities(identifiers: identifiers)
        }
    }

    func entities(matching string: String) async throws -> [NutritionMealEntity] {
        try await MainActor.run {
            try NutritionIntentStore.mealEntities(matching: string)
        }
    }

    func suggestedEntities() async throws -> [NutritionMealEntity] {
        try await MainActor.run {
            try NutritionIntentStore.suggestedMealEntities()
        }
    }
}

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
        WidgetCenter.shared.reloadAllTimelines()
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
        WidgetCenter.shared.reloadAllTimelines()
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
        WidgetCenter.shared.reloadAllTimelines()
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

@MainActor
private enum NutritionIntentStore {
    struct LogResult {
        let summary: String
    }

    struct IntentEnvironment {
        let container: ModelContainer
        let context: ModelContext
        let user: User
        let repository: LocalNutritionRepository
        let service: NutritionService
    }

    enum IntentError: LocalizedError {
        case noAccount
        case noValues
        case unavailableFood
        case unavailableMeal
        case amountMustBePositive(String)
        case negativeValue(String)
        case missingCustomName
        case missingCustomAmount
        case invalidCustomName
        case reservedCustomName(String)

        var errorDescription: String? {
            switch self {
            case .noAccount:
                return "Create or sign in to an account before logging nutrition."
            case .noValues:
                return "Add at least one nutrition value before logging."
            case .unavailableFood:
                return "That food is no longer available."
            case .unavailableMeal:
                return "That meal is no longer available."
            case .amountMustBePositive(let name):
                return "\(name) must be greater than 0."
            case .negativeValue(let name):
                return "\(name) cannot be negative."
            case .missingCustomName:
                return "Add a custom nutrient name, or remove the custom nutrient amount."
            case .missingCustomAmount:
                return "Add an amount for the custom nutrient."
            case .invalidCustomName:
                return "Custom nutrient name must include at least one letter or number."
            case .reservedCustomName(let name):
                return "Use the dedicated \(name) field instead of Custom Nutrient."
            }
        }
    }

    static func logQuickAdd(
        calories: Double?,
        protein: Double?,
        carbs: Double?,
        fat: Double?,
        fiber: Double?,
        sodium: Double?,
        totalSugars: Double?,
        customNutrientName: String?,
        customNutrientAmount: Double?,
        category: FoodLogCategory,
        note: String?
    ) throws -> LogResult {
        try validateNonNegative("Calories", calories)
        try validateNonNegative("Protein", protein)
        try validateNonNegative("Carbohydrates", carbs)
        try validateNonNegative("Fat", fat)
        try validateNonNegative("Fiber", fiber)
        try validateNonNegative("Sodium", sodium)
        try validateNonNegative("Total Sugars", totalSugars)
        try validateNonNegative("Custom Nutrient Amount", customNutrientAmount)

        let extras = try extraNutrients(
            fiber: fiber,
            sodium: sodium,
            totalSugars: totalSugars,
            customNutrientName: customNutrientName,
            customNutrientAmount: customNutrientAmount
        )
        guard hasAnyProvidedValue(calories, protein, carbs, fat, extras: extras) else {
            throw IntentError.noValues
        }

        let environment = try makeEnvironment()

        _ = try environment.service.addQuickNutritionLog(
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            extraNutrients: extras,
            timestamp: Date(),
            category: category,
            note: normalizedOptionalText(note)
        )

        return LogResult(summary: summary(calories: calories, protein: protein, carbs: carbs, fat: fat, extras: extras))
    }

    static func logFood(
        food entity: NutritionFoodEntity,
        amount: Double,
        amountType: NutritionFoodAmountType,
        category: FoodLogCategory,
        note: String?
    ) throws -> LogResult {
        guard amount > 0 else {
            throw IntentError.amountMustBePositive("Amount")
        }

        let environment = try makeEnvironment()
        guard let food = environment.service.foods.first(where: { $0.id == entity.id }) else {
            throw IntentError.unavailableFood
        }

        let resolved = resolvedFoodAmount(food: food, amount: amount, amountType: amountType)
        _ = try environment.service.addFoodLog(
            food: food,
            grams: resolved.amount,
            timestamp: Date(),
            category: category,
            note: normalizedOptionalText(note),
            amountMode: resolved.amountMode,
            servingCount: resolved.servingCount
        )

        return LogResult(summary: "\(resolved.summary) of \(food.name)")
    }

    static func logMeal(
        meal entity: NutritionMealEntity,
        servings: Double,
        category: FoodLogCategory,
        note: String?
    ) throws -> LogResult {
        guard servings > 0 else {
            throw IntentError.amountMustBePositive("Servings")
        }

        let environment = try makeEnvironment()
        guard let meal = environment.service.meals.first(where: { $0.id == entity.id }) else {
            throw IntentError.unavailableMeal
        }

        _ = try environment.service.logMeal(
            template: meal,
            amount: servings,
            timestamp: Date(),
            category: category,
            note: normalizedOptionalText(note)
        )

        let unit = normalizedOptionalText(meal.servingUnitLabel) ?? "serving"
        return LogResult(summary: "\(displayAmount(servings)) \(unit) of \(meal.name)")
    }

    static func foodEntities(identifiers: [UUID]) throws -> [NutritionFoodEntity] {
        let environment = try makeEnvironment()
        let order = Dictionary(uniqueKeysWithValues: identifiers.enumerated().map { ($1, $0) })
        return environment.service.foods
            .filter { order[$0.id] != nil }
            .sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
            .map(foodEntity)
    }

    static func foodEntities(matching string: String) throws -> [NutritionFoodEntity] {
        let environment = try makeEnvironment()
        let query = normalizedOptionalText(string)
        let foods = environment.service.fetchFoods(search: query)
        return Array(foods.prefix(20)).map(foodEntity)
    }

    static func suggestedFoodEntities() throws -> [NutritionFoodEntity] {
        let environment = try makeEnvironment()
        let suggestedFoods = orderedUniqueFoods(
            environment.service.fetchFavoriteFoods()
                + environment.service.fetchRecentFoods(days: 30)
                + environment.service.fetchFoods()
        )
        return Array(suggestedFoods.prefix(20)).map(foodEntity)
    }

    static func mealEntities(identifiers: [UUID]) throws -> [NutritionMealEntity] {
        let environment = try makeEnvironment()
        let order = Dictionary(uniqueKeysWithValues: identifiers.enumerated().map { ($1, $0) })
        return environment.service.meals
            .filter { order[$0.id] != nil }
            .sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
            .map(mealEntity)
    }

    static func mealEntities(matching string: String) throws -> [NutritionMealEntity] {
        let environment = try makeEnvironment()
        let query = normalizedOptionalText(string)
        let meals = environment.service.fetchMeals(search: query)
        return Array(meals.prefix(20)).map(mealEntity)
    }

    static func suggestedMealEntities() throws -> [NutritionMealEntity] {
        let environment = try makeEnvironment()
        return Array(environment.service.fetchMeals().prefix(20)).map(mealEntity)
    }

    private static func makeEnvironment() throws -> IntentEnvironment {
        let container = SharedModelConfig.createSharedModelContainer()
        let context = ModelContext(container)
        let user = try currentUser(in: context)
        try NutritionDataBackfillService(context: context).backfill(userId: user.id)

        let repository = LocalNutritionRepository(modelContext: context)
        let service = NutritionService(context: context, repository: repository)
        service.currentUser = user
        service.loadFoods()
        service.loadMeals()
        service.loadNutrientDefinitions()

        return IntentEnvironment(
            container: container,
            context: context,
            user: user,
            repository: repository,
            service: service
        )
    }

    private static func currentUser(in context: ModelContext) throws -> User {
        let descriptor = FetchDescriptor<User>(
            sortBy: [SortDescriptor(\.lastLogin, order: .reverse)]
        )
        let users = try context.fetch(descriptor).filter { !$0.soft_deleted }
        guard let user = users.first else {
            throw IntentError.noAccount
        }
        return user
    }

    private static func foodEntity(_ food: FoodItem) -> NutritionFoodEntity {
        NutritionFoodEntity(
            id: food.id,
            name: food.name,
            subtitle: foodSubtitle(food)
        )
    }

    private static func mealEntity(_ meal: MealRecipe) -> NutritionMealEntity {
        NutritionMealEntity(
            id: meal.id,
            name: meal.name,
            subtitle: mealSubtitle(meal)
        )
    }

    private static func foodSubtitle(_ food: FoodItem) -> String {
        var parts: [String] = []
        if let brand = normalizedOptionalText(food.brand) {
            parts.append(brand)
        }
        if let servingQuantity = food.servingQuantity,
           let servingUnit = normalizedOptionalText(food.servingUnitLabel) {
            parts.append("\(displayAmount(servingQuantity))\(food.unit.shortLabel) per \(servingUnit)")
        } else {
            parts.append("\(displayAmount(food.referenceQuantity))\(food.unit.shortLabel)")
        }
        return parts.joined(separator: " · ")
    }

    private static func mealSubtitle(_ meal: MealRecipe) -> String {
        let unit = normalizedOptionalText(meal.servingUnitLabel) ?? "serving"
        return "\(displayAmount(meal.batchSize)) \(unit)"
    }

    private static func orderedUniqueFoods(_ foods: [FoodItem]) -> [FoodItem] {
        var seen: Set<UUID> = []
        var ordered: [FoodItem] = []
        for food in foods where !seen.contains(food.id) {
            seen.insert(food.id)
            ordered.append(food)
        }
        return ordered
    }

    private static func resolvedFoodAmount(
        food: FoodItem,
        amount: Double,
        amountType: NutritionFoodAmountType
    ) -> (amount: Double, amountMode: NutritionLogAmountMode, servingCount: Double?, summary: String) {
        switch amountType {
        case .serving:
            if let servingQuantity = food.servingQuantity, servingQuantity > 0 {
                let unit = normalizedOptionalText(food.servingUnitLabel) ?? "serving"
                return (
                    amount: servingQuantity * amount,
                    amountMode: .serving,
                    servingCount: amount,
                    summary: "\(displayAmount(amount)) \(unit)"
                )
            }
            return (
                amount: food.referenceQuantity * amount,
                amountMode: .baseUnit,
                servingCount: nil,
                summary: "\(displayAmount(food.referenceQuantity * amount))\(food.unit.shortLabel)"
            )
        case .foodUnit:
            return (
                amount: amount,
                amountMode: .baseUnit,
                servingCount: nil,
                summary: "\(displayAmount(amount))\(food.unit.shortLabel)"
            )
        }
    }

    private static func extraNutrients(
        fiber: Double?,
        sodium: Double?,
        totalSugars: Double?,
        customNutrientName: String?,
        customNutrientAmount: Double?
    ) throws -> [String: Double]? {
        var extras: [String: Double] = [:]
        if let fiber {
            extras["fiber"] = max(0, fiber)
        }
        if let sodium {
            extras["sodium"] = max(0, sodium)
        }
        if let totalSugars {
            extras["total-sugars"] = max(0, totalSugars)
        }

        let customName = normalizedOptionalText(customNutrientName)
        if customName == nil, customNutrientAmount != nil {
            throw IntentError.missingCustomName
        }
        if customName != nil, customNutrientAmount == nil {
            throw IntentError.missingCustomAmount
        }
        if let customName, let customNutrientAmount {
            let key = NutritionNutrientKey.normalized(customName)
            guard !key.isEmpty else {
                throw IntentError.invalidCustomName
            }
            if NutritionNutrientKey.coreKeySet.contains(key) {
                throw IntentError.reservedCustomName(customName)
            }
            extras[key] = max(0, customNutrientAmount)
        }

        return extras.isEmpty ? nil : extras
    }

    private static func hasAnyProvidedValue(
        _ values: Double?...,
        extras: [String: Double]?
    ) -> Bool {
        values.contains { $0 != nil } || extras?.isEmpty == false
    }

    private static func validateNonNegative(_ name: String, _ value: Double?) throws {
        guard let value else { return }
        if value < 0 {
            throw IntentError.negativeValue(name)
        }
    }

    private static func normalizedOptionalText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func summary(
        calories: Double?,
        protein: Double?,
        carbs: Double?,
        fat: Double?,
        extras: [String: Double]?
    ) -> String {
        var parts: [String] = []
        if let calories {
            parts.append("\(displayAmount(calories)) kcal")
        }
        if let protein {
            parts.append("\(displayAmount(protein))g protein")
        }
        if let carbs {
            parts.append("\(displayAmount(carbs))g carbs")
        }
        if let fat {
            parts.append("\(displayAmount(fat))g fat")
        }
        for (key, value) in (extras ?? [:]).sorted(by: { $0.key < $1.key }) {
            parts.append("\(displayAmount(value)) \(key.replacingOccurrences(of: "-", with: " "))")
        }
        return parts.isEmpty ? "nutrition" : parts.joined(separator: ", ")
    }

    private static func displayAmount(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return SetDisplayFormatter.formatDecimal(value)
    }
}
