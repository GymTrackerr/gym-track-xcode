import Foundation

protocol NutritionRepositoryProtocol {
    func fetchFoodItems(for userId: UUID) throws -> [FoodItem]
    func fetchMealRecipes(for userId: UUID) throws -> [MealRecipe]
    func fetchNutritionLogs(for userId: UUID, between start: Date, and end: Date) throws -> [NutritionLogEntry]
    func fetchNutritionLogs(for userId: UUID, in interval: DateInterval) throws -> [NutritionLogEntry]
    func fetchTargets() throws -> [NutritionTarget]
    func insertFoodItem(_ food: FoodItem) throws
    func saveFoodItem(_ food: FoodItem) throws
    func insertMealRecipe(_ meal: MealRecipe) throws
    func saveMealRecipe(_ meal: MealRecipe) throws
    func replaceMealRecipeItems(
        on meal: MealRecipe,
        with items: [(foodItem: FoodItem, amount: Double, amountUnit: FoodItemUnit)]
    ) throws
    func softDeleteMealRecipe(_ meal: MealRecipe) throws
    func insertNutritionLogEntry(_ log: NutritionLogEntry) throws
    func saveNutritionLogEntry(_ log: NutritionLogEntry) throws
    func softDeleteNutritionLogEntry(_ log: NutritionLogEntry) throws
    func insertNutritionTarget(_ target: NutritionTarget) throws
    func saveNutritionTarget(_ target: NutritionTarget) throws
}
