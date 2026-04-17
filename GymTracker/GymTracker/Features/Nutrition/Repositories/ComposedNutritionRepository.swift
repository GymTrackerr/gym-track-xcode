import Foundation

final class ComposedNutritionRepository: NutritionRepositoryProtocol {
    private let catalogRepository: NutritionCatalogRepositoryProtocol
    private let logRepository: NutritionLogRepositoryProtocol
    private let targetRepository: NutritionTargetRepositoryProtocol

    init(
        catalogRepository: NutritionCatalogRepositoryProtocol,
        logRepository: NutritionLogRepositoryProtocol,
        targetRepository: NutritionTargetRepositoryProtocol
    ) {
        self.catalogRepository = catalogRepository
        self.logRepository = logRepository
        self.targetRepository = targetRepository
    }

    func fetchFoodItems(for userId: UUID) throws -> [FoodItem] {
        try catalogRepository.fetchFoodItems(for: userId)
    }

    func fetchMealRecipes(for userId: UUID) throws -> [MealRecipe] {
        try catalogRepository.fetchMealRecipes(for: userId)
    }

    func fetchNutritionLogs(for userId: UUID, between start: Date, and end: Date) throws -> [NutritionLogEntry] {
        try logRepository.fetchNutritionLogs(for: userId, between: start, and: end)
    }

    func fetchNutritionLogs(for userId: UUID, in interval: DateInterval) throws -> [NutritionLogEntry] {
        try logRepository.fetchNutritionLogs(for: userId, in: interval)
    }

    func fetchNutritionLogBounds(for userId: UUID) throws -> (oldest: Date?, newest: Date?) {
        try logRepository.fetchNutritionLogBounds(for: userId)
    }

    func fetchTargets() throws -> [NutritionTarget] {
        try targetRepository.fetchTargets()
    }

    func insertFoodItem(_ food: FoodItem) throws {
        try catalogRepository.insertFoodItem(food)
    }

    func saveFoodItem(_ food: FoodItem) throws {
        try catalogRepository.saveFoodItem(food)
    }

    func insertMealRecipe(_ meal: MealRecipe) throws {
        try catalogRepository.insertMealRecipe(meal)
    }

    func saveMealRecipe(_ meal: MealRecipe) throws {
        try catalogRepository.saveMealRecipe(meal)
    }

    func replaceMealRecipeItems(
        on meal: MealRecipe,
        with items: [(foodItem: FoodItem, amount: Double, amountUnit: FoodItemUnit)]
    ) throws {
        try catalogRepository.replaceMealRecipeItems(on: meal, with: items)
    }

    func softDeleteMealRecipe(_ meal: MealRecipe) throws {
        try catalogRepository.softDeleteMealRecipe(meal)
    }

    func insertNutritionLogEntry(_ log: NutritionLogEntry) throws {
        try logRepository.insertNutritionLogEntry(log)
    }

    func saveNutritionLogEntry(_ log: NutritionLogEntry) throws {
        try logRepository.saveNutritionLogEntry(log)
    }

    func softDeleteNutritionLogEntry(_ log: NutritionLogEntry) throws {
        try logRepository.softDeleteNutritionLogEntry(log)
    }

    func insertNutritionTarget(_ target: NutritionTarget) throws {
        try targetRepository.insertNutritionTarget(target)
    }

    func saveNutritionTarget(_ target: NutritionTarget) throws {
        try targetRepository.saveNutritionTarget(target)
    }
}
