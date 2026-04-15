import Foundation
import SwiftData

final class LocalNutritionRepository: NutritionRepositoryProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchFoodItems(for userId: UUID) throws -> [FoodItem] {
        let descriptor = FetchDescriptor<FoodItem>(
            predicate: #Predicate<FoodItem> { item in
                item.userId == userId && item.soft_deleted == false && item.isArchived == false
            },
            sortBy: [SortDescriptor(\.name)]
        )
        let items = try modelContext.fetch(descriptor)
        if try SyncRootMetadataManager.prepareForRead(items, in: modelContext) {
            try modelContext.save()
        }
        return items
    }

    func fetchMealRecipes(for userId: UUID) throws -> [MealRecipe] {
        let descriptor = FetchDescriptor<MealRecipe>(
            predicate: #Predicate<MealRecipe> { meal in
                meal.userId == userId && meal.soft_deleted == false && meal.isArchived == false
            },
            sortBy: [SortDescriptor(\.name)]
        )
        let meals = try modelContext.fetch(descriptor)
        if try SyncRootMetadataManager.prepareForRead(meals, in: modelContext) {
            try modelContext.save()
        }
        return meals
    }

    func fetchNutritionLogs(for userId: UUID, between start: Date, and end: Date) throws -> [NutritionLogEntry] {
        let descriptor = FetchDescriptor<NutritionLogEntry>(
            predicate: #Predicate<NutritionLogEntry> { log in
                log.userId == userId && log.soft_deleted == false && log.timestamp >= start && log.timestamp < end
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        let logs = try modelContext.fetch(descriptor)
        if try SyncRootMetadataManager.prepareForRead(logs, in: modelContext) {
            try modelContext.save()
        }
        return logs
    }

    func fetchNutritionLogs(for userId: UUID, in interval: DateInterval) throws -> [NutritionLogEntry] {
        try fetchNutritionLogs(for: userId, between: interval.start, and: interval.end)
    }

    func fetchTargets() throws -> [NutritionTarget] {
        let descriptor = FetchDescriptor<NutritionTarget>(
            predicate: #Predicate<NutritionTarget> { target in
                target.soft_deleted == false
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let targets = try modelContext.fetch(descriptor)
        if try SyncRootMetadataManager.prepareForRead(targets, in: modelContext) {
            try modelContext.save()
        }
        return targets
    }

    func insertFoodItem(_ food: FoodItem) throws {
        modelContext.insert(food)
        try SyncRootMetadataManager.markCreated(food, in: modelContext)
        try modelContext.save()
    }

    func saveFoodItem(_ food: FoodItem) throws {
        try SyncRootMetadataManager.markUpdated(food, in: modelContext)
        try modelContext.save()
    }

    func insertMealRecipe(_ meal: MealRecipe) throws {
        modelContext.insert(meal)
        try SyncRootMetadataManager.markCreated(meal, in: modelContext)
        try modelContext.save()
    }

    func saveMealRecipe(_ meal: MealRecipe) throws {
        try SyncRootMetadataManager.markUpdated(meal, in: modelContext)
        try modelContext.save()
    }

    func replaceMealRecipeItems(
        on meal: MealRecipe,
        with items: [(foodItem: FoodItem, amount: Double, amountUnit: FoodItemUnit)]
    ) throws {
        for existingItem in meal.items {
            modelContext.delete(existingItem)
        }
        meal.items.removeAll()

        for (index, item) in items.enumerated() {
            let recipeItem = MealRecipeItem(
                amount: item.amount,
                amountUnit: item.amountUnit,
                order: index,
                mealRecipe: meal,
                foodItem: item.foodItem
            )
            meal.items.append(recipeItem)
        }

        try SyncRootMetadataManager.markUpdated(meal, in: modelContext)
        try modelContext.save()
    }

    func softDeleteMealRecipe(_ meal: MealRecipe) throws {
        try SyncRootMetadataManager.markSoftDeleted(meal, in: modelContext)
        try modelContext.save()
    }

    func insertNutritionLogEntry(_ log: NutritionLogEntry) throws {
        modelContext.insert(log)
        try SyncRootMetadataManager.markCreated(log, in: modelContext)
        try modelContext.save()
    }

    func saveNutritionLogEntry(_ log: NutritionLogEntry) throws {
        try SyncRootMetadataManager.markUpdated(log, in: modelContext)
        try modelContext.save()
    }

    func softDeleteNutritionLogEntry(_ log: NutritionLogEntry) throws {
        try SyncRootMetadataManager.markSoftDeleted(log, in: modelContext)
        try modelContext.save()
    }

    func insertNutritionTarget(_ target: NutritionTarget) throws {
        modelContext.insert(target)
        try SyncRootMetadataManager.markCreated(target, in: modelContext)
        try modelContext.save()
    }

    func saveNutritionTarget(_ target: NutritionTarget) throws {
        try SyncRootMetadataManager.markUpdated(target, in: modelContext)
        try modelContext.save()
    }
}
