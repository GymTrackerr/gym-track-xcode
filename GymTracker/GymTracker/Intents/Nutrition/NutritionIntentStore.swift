import Foundation
import SwiftData

@MainActor
enum NutritionIntentStore {
    struct LogResult {
        let summary: String
    }

    private struct IntentEnvironment {
        let container: ModelContainer
        let context: ModelContext
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
        return orderedMatches(
            identifiers: identifiers,
            items: environment.service.foods,
            id: \.id
        )
        .map(foodEntity)
    }

    static func foodEntities(matching string: String) throws -> [NutritionFoodEntity] {
        let environment = try makeEnvironment()
        let query = normalizedOptionalText(string)
        return Array(environment.service.fetchFoods(search: query).prefix(20)).map(foodEntity)
    }

    static func suggestedFoodEntities() throws -> [NutritionFoodEntity] {
        let environment = try makeEnvironment()
        let suggestedFoods = orderedUnique(
            environment.service.fetchFavoriteFoods()
                + environment.service.fetchRecentFoods(days: 30)
                + environment.service.fetchFoods(),
            id: \.id
        )
        return Array(suggestedFoods.prefix(20)).map(foodEntity)
    }

    static func mealEntities(identifiers: [UUID]) throws -> [NutritionMealEntity] {
        let environment = try makeEnvironment()
        return orderedMatches(
            identifiers: identifiers,
            items: environment.service.meals,
            id: \.id
        )
        .map(mealEntity)
    }

    static func mealEntities(matching string: String) throws -> [NutritionMealEntity] {
        let environment = try makeEnvironment()
        let query = normalizedOptionalText(string)
        return Array(environment.service.fetchMeals(search: query).prefix(20)).map(mealEntity)
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
        return parts.joined(separator: " - ")
    }

    private static func mealSubtitle(_ meal: MealRecipe) -> String {
        let unit = normalizedOptionalText(meal.servingUnitLabel) ?? "serving"
        return "\(displayAmount(meal.batchSize)) \(unit)"
    }

    private static func orderedMatches<Item>(
        identifiers: [UUID],
        items: [Item],
        id: KeyPath<Item, UUID>
    ) -> [Item] {
        let order = Dictionary(uniqueKeysWithValues: identifiers.enumerated().map { ($1, $0) })
        return items
            .filter { order[$0[keyPath: id]] != nil }
            .sorted { (order[$0[keyPath: id]] ?? 0) < (order[$1[keyPath: id]] ?? 0) }
    }

    private static func orderedUnique<Item>(_ items: [Item], id: KeyPath<Item, UUID>) -> [Item] {
        var seen: Set<UUID> = []
        var ordered: [Item] = []
        for item in items {
            let itemId = item[keyPath: id]
            guard !seen.contains(itemId) else { continue }
            seen.insert(itemId)
            ordered.append(item)
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
