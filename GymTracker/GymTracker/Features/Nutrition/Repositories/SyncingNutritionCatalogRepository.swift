import Foundation

final class SyncingNutritionCatalogRepository: BaseSyncRepository, NutritionCatalogRepositoryProtocol {
    private let localRepository: NutritionCatalogRepositoryProtocol

    init(
        localRepository: NutritionCatalogRepositoryProtocol,
        queueStore: SyncQueueStore,
        eligibilityService: SyncEligibilityService
    ) {
        super.init(queueStore: queueStore, eligibilityService: eligibilityService)
        self.localRepository = localRepository
    }

    func fetchFoodItems(for userId: UUID) throws -> [FoodItem] {
        try localRepository.fetchFoodItems(for: userId)
    }

    func fetchMealRecipes(for userId: UUID) throws -> [MealRecipe] {
        try localRepository.fetchMealRecipes(for: userId)
    }

    func insertFoodItem(_ food: FoodItem) throws {
        try localRepository.insertFoodItem(food)
        enqueueRootMutationIfNeeded(root: food, operation: .create)
    }

    func saveFoodItem(_ food: FoodItem) throws {
        try localRepository.saveFoodItem(food)
        enqueueRootMutationIfNeeded(root: food, operation: .update)
    }

    func insertMealRecipe(_ meal: MealRecipe) throws {
        try localRepository.insertMealRecipe(meal)
        enqueueRootMutationIfNeeded(root: meal, operation: .create)
    }

    func saveMealRecipe(_ meal: MealRecipe) throws {
        try localRepository.saveMealRecipe(meal)
        enqueueRootMutationIfNeeded(root: meal, operation: .update)
    }

    func replaceMealRecipeItems(
        on meal: MealRecipe,
        with items: [(foodItem: FoodItem, amount: Double, amountUnit: FoodItemUnit)]
    ) throws {
        try localRepository.replaceMealRecipeItems(on: meal, with: items)
        enqueueRootMutationIfNeeded(root: meal, operation: .update)
    }

    func softDeleteMealRecipe(_ meal: MealRecipe) throws {
        try localRepository.softDeleteMealRecipe(meal)
        enqueueRootMutationIfNeeded(root: meal, operation: .softDelete)
    }
}
