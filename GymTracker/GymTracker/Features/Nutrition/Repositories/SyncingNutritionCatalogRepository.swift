import Foundation

final class SyncingNutritionCatalogRepository: NutritionCatalogRepositoryProtocol {
    private let localRepository: NutritionCatalogRepositoryProtocol
    private let queueStore: SyncQueueStore
    private let eligibilityService: SyncEligibilityService

    init(
        localRepository: NutritionCatalogRepositoryProtocol,
        queueStore: SyncQueueStore,
        eligibilityService: SyncEligibilityService
    ) {
        self.localRepository = localRepository
        self.queueStore = queueStore
        self.eligibilityService = eligibilityService
    }

    func fetchFoodItems(for userId: UUID) throws -> [FoodItem] {
        try localRepository.fetchFoodItems(for: userId)
    }

    func fetchMealRecipes(for userId: UUID) throws -> [MealRecipe] {
        try localRepository.fetchMealRecipes(for: userId)
    }

    func insertFoodItem(_ food: FoodItem) throws {
        try localRepository.insertFoodItem(food)
        SyncQueueMutationWriter.enqueueIfNeeded(
            root: food,
            operation: .create,
            queueStore: queueStore,
            eligibilityService: eligibilityService
        )
    }

    func saveFoodItem(_ food: FoodItem) throws {
        try localRepository.saveFoodItem(food)
        SyncQueueMutationWriter.enqueueIfNeeded(
            root: food,
            operation: .update,
            queueStore: queueStore,
            eligibilityService: eligibilityService
        )
    }

    func insertMealRecipe(_ meal: MealRecipe) throws {
        try localRepository.insertMealRecipe(meal)
        SyncQueueMutationWriter.enqueueIfNeeded(
            root: meal,
            operation: .create,
            queueStore: queueStore,
            eligibilityService: eligibilityService
        )
    }

    func saveMealRecipe(_ meal: MealRecipe) throws {
        try localRepository.saveMealRecipe(meal)
        SyncQueueMutationWriter.enqueueIfNeeded(
            root: meal,
            operation: .update,
            queueStore: queueStore,
            eligibilityService: eligibilityService
        )
    }

    func replaceMealRecipeItems(
        on meal: MealRecipe,
        with items: [(foodItem: FoodItem, amount: Double, amountUnit: FoodItemUnit)]
    ) throws {
        try localRepository.replaceMealRecipeItems(on: meal, with: items)
        SyncQueueMutationWriter.enqueueIfNeeded(
            root: meal,
            operation: .update,
            queueStore: queueStore,
            eligibilityService: eligibilityService
        )
    }

    func softDeleteMealRecipe(_ meal: MealRecipe) throws {
        try localRepository.softDeleteMealRecipe(meal)
        SyncQueueMutationWriter.enqueueIfNeeded(
            root: meal,
            operation: .softDelete,
            queueStore: queueStore,
            eligibilityService: eligibilityService
        )
    }
}
