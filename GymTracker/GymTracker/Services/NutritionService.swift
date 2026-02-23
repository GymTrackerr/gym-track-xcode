//
//  NutritionService.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2026-02-23.
//
import Foundation
import SwiftUI
import SwiftData
import Combine
internal import CoreData

class NutritionService: ServiceBase, ObservableObject {
    enum NutritionError: LocalizedError {
        case missingUser
        case validation(String)
        case persistence(String)

        var errorDescription: String? {
            switch self {
            case .missingUser:
                return "You must be signed in to save nutrition data."
            case .validation(let message):
                return message
            case .persistence(let message):
                return message
            }
        }
    }

    struct MealInputItem {
        let food: Food
        let grams: Double
    }

    @Published var foods: [Food] = []
    @Published var meals: [Meal] = []
    @Published var dayLogs: [FoodLog] = []
    @Published var dayMealEntries: [MealEntry] = []

    override func loadFeature() {
        loadFoods()
        loadMeals()
        loadDayData(for: Date())
    }

    func loadFoods() {
        guard let userId = currentUser?.id else {
            foods = []
            return
        }

        let descriptor = FetchDescriptor<Food>(
            predicate: #Predicate<Food> { food in
                food.userId == userId
            },
            sortBy: [SortDescriptor(\.name)]
        )

        do {
            foods = try modelContext.fetch(descriptor)
        } catch {
            foods = []
            print("Failed to fetch foods: \(error)")
        }
    }

    func fetchFoods(search: String? = nil, includeArchived: Bool = false) -> [Food] {
        let query = search?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return foods
            .filter { includeArchived || !$0.isArchived }
            .filter { food in
                guard !query.isEmpty else { return true }
                return food.name.localizedCaseInsensitiveContains(query)
                    || (food.brand?.localizedCaseInsensitiveContains(query) ?? false)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func fetchFavoriteFoods(includeArchived: Bool = false) -> [Food] {
        fetchFoods(search: nil, includeArchived: includeArchived)
            .filter { $0.isFavorite }
    }

    func fetchRecentFoods(days: Int = 14, includeArchived: Bool = false) -> [Food] {
        guard let userId = currentUser?.id else { return [] }
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -max(days, 1), to: now) ?? now

        let descriptor = FetchDescriptor<FoodLog>(
            predicate: #Predicate<FoodLog> { log in
                log.userId == userId && log.timestamp >= start
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        do {
            let logs = try modelContext.fetch(descriptor)
            var seen: Set<UUID> = []
            var ordered: [Food] = []

            for log in logs {
                let food = log.food
                if !includeArchived && food.isArchived { continue }
                if seen.contains(food.id) { continue }
                seen.insert(food.id)
                ordered.append(food)
            }

            return ordered
        } catch {
            print("Failed to fetch recent foods: \(error)")
            return []
        }
    }

    func searchFoods(query: String) -> [Food] {
        fetchFoods(search: query)
    }

    @discardableResult
    func createFood(
        name: String,
        brand: String?,
        referenceLabel: String?,
        gramsPerReference: Double,
        kcalPerReference: Double,
        proteinPerReference: Double,
        carbPerReference: Double,
        fatPerReference: Double
    ) -> Food? {
        guard let userId = currentUser?.id else { return nil }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        guard gramsPerReference > 0 else { return nil }
        guard kcalPerReference >= 0, proteinPerReference >= 0, carbPerReference >= 0, fatPerReference >= 0 else {
            return nil
        }

        let food = Food(
            userId: userId,
            name: trimmedName,
            brand: normalizedOptionalText(brand),
            referenceLabel: normalizedOptionalText(referenceLabel),
            gramsPerReference: gramsPerReference,
            kcalPerReference: kcalPerReference,
            proteinPerReference: proteinPerReference,
            carbPerReference: carbPerReference,
            fatPerReference: fatPerReference
        )

        modelContext.insert(food)

        do {
            try modelContext.save()
            loadFoods()
            return food
        } catch {
            print("Failed to save food: \(error)")
            return nil
        }
    }

    @discardableResult
    func addFood(
        name: String,
        brand: String?,
        referenceLabel: String?,
        gramsPerReference: Double,
        kcalPerReference: Double,
        proteinPerReference: Double,
        carbPerReference: Double,
        fatPerReference: Double
    ) -> Food? {
        createFood(
            name: name,
            brand: brand,
            referenceLabel: referenceLabel,
            gramsPerReference: gramsPerReference,
            kcalPerReference: kcalPerReference,
            proteinPerReference: proteinPerReference,
            carbPerReference: carbPerReference,
            fatPerReference: fatPerReference
        )
    }

    func updateFood(
        _ food: Food,
        name: String,
        brand: String?,
        referenceLabel: String?,
        gramsPerReference: Double,
        kcalPerReference: Double,
        proteinPerReference: Double,
        carbPerReference: Double,
        fatPerReference: Double
    ) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        guard gramsPerReference > 0 else { return false }
        guard kcalPerReference >= 0, proteinPerReference >= 0, carbPerReference >= 0, fatPerReference >= 0 else {
            return false
        }

        food.update(
            name: trimmedName,
            brand: normalizedOptionalText(brand),
            referenceLabel: normalizedOptionalText(referenceLabel),
            gramsPerReference: gramsPerReference,
            kcalPerReference: kcalPerReference,
            proteinPerReference: proteinPerReference,
            carbPerReference: carbPerReference,
            fatPerReference: fatPerReference
        )

        do {
            try modelContext.save()
            loadFoods()
            return true
        } catch {
            print("Failed to update food: \(error)")
            return false
        }
    }

    func toggleFavorite(food: Food) {
        food.isFavorite.toggle()
        food.updatedAt = Date()

        do {
            try modelContext.save()
            loadFoods()
        } catch {
            print("Failed to toggle favorite: \(error)")
        }
    }

    func archiveFood(food: Food) throws {
        food.isArchived = true
        food.updatedAt = Date()

        do {
            try modelContext.save()
            loadFoods()
        } catch {
            throw NutritionError.persistence("Could not archive this food. Please try again.")
        }
    }

    func unarchiveFood(food: Food) throws {
        food.isArchived = false
        food.updatedAt = Date()

        do {
            try modelContext.save()
            loadFoods()
        } catch {
            throw NutritionError.persistence("Could not unarchive this food. Please try again.")
        }
    }

    // Legacy compatibility: foods are never hard-deleted.
    func deleteFood(_ food: Food) -> Bool {
        do {
            try archiveFood(food: food)
            return true
        } catch {
            return false
        }
    }

    func loadMeals() {
        guard let userId = currentUser?.id else {
            meals = []
            return
        }

        let descriptor = FetchDescriptor<Meal>(
            predicate: #Predicate<Meal> { meal in
                meal.userId == userId
            },
            sortBy: [SortDescriptor(\.name)]
        )

        do {
            meals = try modelContext.fetch(descriptor)
        } catch {
            meals = []
            print("Failed to fetch meals: \(error)")
        }
    }

    @discardableResult
    func createMealTemplate(name: String, items: [MealInputItem]) -> Meal? {
        guard let userId = currentUser?.id else { return nil }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        let validItems = items.compactMap { item -> MealInputItem? in
            guard item.grams > 0 else { return nil }
            return MealInputItem(food: item.food, grams: item.grams)
        }

        guard !validItems.isEmpty else { return nil }

        let meal = Meal(userId: userId, name: trimmedName)

        for (index, item) in validItems.enumerated() {
            let mealItem = MealItem(order: index, grams: item.grams, meal: meal, food: item.food)
            meal.items.append(mealItem)
        }

        modelContext.insert(meal)

        do {
            try modelContext.save()
            loadMeals()
            return meal
        } catch {
            print("Failed to save meal: \(error)")
            return nil
        }
    }

    @discardableResult
    func addMeal(name: String, items: [MealInputItem]) -> Meal? {
        createMealTemplate(name: name, items: items)
    }

    func updateMeal(_ meal: Meal, name: String, items: [MealInputItem]) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }

        let validItems = items.compactMap { item -> MealInputItem? in
            guard item.grams > 0 else { return nil }
            return MealInputItem(food: item.food, grams: item.grams)
        }

        guard !validItems.isEmpty else { return false }

        meal.name = trimmedName
        meal.updatedAt = Date()

        for existingItem in meal.items {
            modelContext.delete(existingItem)
        }
        meal.items.removeAll()

        for (index, item) in validItems.enumerated() {
            let mealItem = MealItem(order: index, grams: item.grams, meal: meal, food: item.food)
            meal.items.append(mealItem)
        }

        do {
            try modelContext.save()
            loadMeals()
            return true
        } catch {
            print("Failed to update meal: \(error)")
            return false
        }
    }

    func deleteMeal(_ meal: Meal) {
        modelContext.delete(meal)

        do {
            try modelContext.save()
            loadMeals()
        } catch {
            print("Failed to delete meal: \(error)")
        }
    }

    @discardableResult
    func logMeal(
        template: Meal,
        timestamp: Date,
        category: FoodLogCategory,
        note: String?
    ) throws -> MealEntry {
        guard let userId = currentUser?.id else {
            throw NutritionError.missingUser
        }

        let sortedItems = template.items.sorted { $0.order < $1.order }
        guard !sortedItems.isEmpty else {
            throw NutritionError.validation("Meal template must include at least one item.")
        }

        let mealEntry = MealEntry(
            userId: userId,
            timestamp: timestamp,
            category: category,
            note: normalizedOptionalText(note),
            templateMeal: template
        )
        modelContext.insert(mealEntry)

        for item in sortedItems {
            guard item.grams > 0 else { continue }

            let log = FoodLog(
                userId: userId,
                timestamp: timestamp,
                category: category,
                grams: item.grams,
                note: normalizedOptionalText(note),
                food: item.food,
                mealEntry: mealEntry
            )
            mealEntry.logs.append(log)
            modelContext.insert(log)
        }

        do {
            try modelContext.save()
            loadDayData(for: timestamp)
            loadFoods()
            return mealEntry
        } catch {
            throw NutritionError.persistence("Could not log this meal. Please try again.")
        }
    }

    func loadDayData(for selectedDate: Date) {
        loadDayLogs(for: selectedDate)
        loadDayMealEntries(for: selectedDate)
    }

    func loadDayLogs(for selectedDate: Date) {
        guard let userId = currentUser?.id else {
            dayLogs = []
            return
        }

        let (dayStart, dayEnd) = dayRange(for: selectedDate)

        let descriptor = FetchDescriptor<FoodLog>(
            predicate: #Predicate<FoodLog> { log in
                log.userId == userId
                && log.timestamp >= dayStart
                && log.timestamp < dayEnd
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )

        do {
            dayLogs = try modelContext.fetch(descriptor)
        } catch {
            dayLogs = []
            print("Failed to fetch food logs: \(error)")
        }
    }

    func loadDayMealEntries(for selectedDate: Date) {
        guard let userId = currentUser?.id else {
            dayMealEntries = []
            return
        }

        let (dayStart, dayEnd) = dayRange(for: selectedDate)

        let descriptor = FetchDescriptor<MealEntry>(
            predicate: #Predicate<MealEntry> { entry in
                entry.userId == userId
                && entry.timestamp >= dayStart
                && entry.timestamp < dayEnd
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )

        do {
            dayMealEntries = try modelContext.fetch(descriptor)
        } catch {
            dayMealEntries = []
            print("Failed to fetch meal entries: \(error)")
        }
    }

    @discardableResult
    func addFoodLog(
        food: Food,
        grams: Double,
        timestamp: Date,
        category: FoodLogCategory,
        note: String?
    ) throws -> FoodLog {
        guard let userId = currentUser?.id else {
            throw NutritionError.missingUser
        }
        guard grams > 0 else {
            throw NutritionError.validation("Grams must be greater than 0.")
        }

        let log = FoodLog(
            userId: userId,
            timestamp: timestamp,
            category: category,
            grams: grams,
            note: normalizedOptionalText(note),
            food: food,
            mealEntry: nil
        )

        modelContext.insert(log)

        do {
            try modelContext.save()
            loadDayData(for: timestamp)
            loadFoods()
            return log
        } catch {
            throw NutritionError.persistence("Could not save this food log. Please try again.")
        }
    }

    func updateFoodLog(
        _ log: FoodLog,
        grams: Double,
        timestamp: Date,
        category: FoodLogCategory,
        note: String?
    ) -> Bool {
        guard grams > 0 else { return false }

        log.grams = grams
        log.timestamp = timestamp
        log.category = category
        log.note = normalizedOptionalText(note)

        do {
            try modelContext.save()
            loadDayData(for: timestamp)
            return true
        } catch {
            print("Failed to update food log: \(error)")
            return false
        }
    }

    func deleteFoodLog(_ log: FoodLog, selectedDate: Date) {
        let parentEntry = log.mealEntry
        let shouldDeleteParentEntry = (parentEntry?.logs.count ?? 0) <= 1

        modelContext.delete(log)

        if shouldDeleteParentEntry, let parentEntry {
            modelContext.delete(parentEntry)
        }

        do {
            try modelContext.save()
            loadDayData(for: selectedDate)
            loadFoods()
        } catch {
            print("Failed to delete food log: \(error)")
        }
    }

    func deleteMealEntry(_ entry: MealEntry, selectedDate: Date) {
        modelContext.delete(entry)

        do {
            try modelContext.save()
            loadDayData(for: selectedDate)
            loadFoods()
        } catch {
            print("Failed to delete meal entry: \(error)")
        }
    }

    func totalKcal(for logs: [FoodLog]) -> Double {
        logs.reduce(0) { $0 + $1.kcal }
    }

    func totalProtein(for logs: [FoodLog]) -> Double {
        logs.reduce(0) { $0 + $1.protein }
    }

    func totalCarbs(for logs: [FoodLog]) -> Double {
        logs.reduce(0) { $0 + $1.carbs }
    }

    func totalFat(for logs: [FoodLog]) -> Double {
        logs.reduce(0) { $0 + $1.fat }
    }

    func defaultCategory(for date: Date) -> FoodLogCategory {
        let hour = Calendar.current.component(.hour, from: date)

        switch hour {
        case 5..<11:
            return .breakfast
        case 11..<15:
            return .lunch
        case 15..<21:
            return .dinner
        case 21..<24, 0..<5:
            return .snack
        default:
            return .other
        }
    }

    func dateByPinning(_ time: Date, to selectedDate: Date) -> Date {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: selectedDate)
        let components = calendar.dateComponents([.hour, .minute, .second], from: time)

        return calendar.date(
            bySettingHour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: components.second ?? 0,
            of: day
        ) ?? day
    }

    private func dayRange(for selectedDate: Date) -> (Date, Date) {
        let dayStart = Calendar.current.startOfDay(for: selectedDate)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return (dayStart, dayEnd)
    }

    private func normalizedOptionalText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
