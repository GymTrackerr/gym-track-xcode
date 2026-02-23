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
    @Published var nutritionTarget: NutritionTarget?

    override func loadFeature() {
        loadFoods()
        loadMeals()
        loadDayData(for: Date())
        do {
            nutritionTarget = try getOrCreateTarget()
        } catch {
            nutritionTarget = nil
        }
    }

    func requireUserId() throws -> UUID {
        guard let userId = currentUser?.id else {
            throw NutritionError.missingUser
        }
        return userId
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

    func fetchFoods(search: String? = nil, includeArchived: Bool = false, kind: FoodKind? = nil) -> [Food] {
        let query = search?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return foods
            .filter { includeArchived || !$0.isArchived }
            .filter { food in
                guard let kind else { return true }
                return food.kind == kind
            }
            .filter { food in
                guard !query.isEmpty else { return true }
                return food.name.localizedCaseInsensitiveContains(query)
                    || (food.brand?.localizedCaseInsensitiveContains(query) ?? false)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func fetchFavoriteFoods(includeArchived: Bool = false, kind: FoodKind? = nil) -> [Food] {
        fetchFoods(search: nil, includeArchived: includeArchived, kind: kind)
            .filter { $0.isFavorite }
    }

    func fetchRecentFoods(days: Int = 14, includeArchived: Bool = false, kind: FoodKind? = nil) -> [Food] {
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
                if let kind, food.kind != kind { continue }
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

    @discardableResult
    func createFood(
        name: String,
        brand: String?,
        referenceLabel: String?,
        gramsPerReference: Double,
        kcalPerReference: Double,
        proteinPerReference: Double,
        carbPerReference: Double,
        fatPerReference: Double,
        kind: FoodKind = .food,
        unit: FoodUnit = .grams
    ) -> Food? {
        guard let userId = try? requireUserId() else { return nil }

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
            fatPerReference: fatPerReference,
            kind: kind,
            unit: unit
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
        fatPerReference: Double,
        kind: FoodKind = .food,
        unit: FoodUnit = .grams
    ) -> Food? {
        createFood(
            name: name,
            brand: brand,
            referenceLabel: referenceLabel,
            gramsPerReference: gramsPerReference,
            kcalPerReference: kcalPerReference,
            proteinPerReference: proteinPerReference,
            carbPerReference: carbPerReference,
            fatPerReference: fatPerReference,
            kind: kind,
            unit: unit
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
        fatPerReference: Double,
        kind: FoodKind? = nil,
        unit: FoodUnit? = nil
    ) -> Bool {
        guard let userId = try? requireUserId() else { return false }
        guard food.userId == userId else { return false }

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
            fatPerReference: fatPerReference,
            kind: kind,
            unit: unit
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

    func getOrCreateTarget() throws -> NutritionTarget {
        let descriptor = FetchDescriptor<NutritionTarget>(
            sortBy: [SortDescriptor(\.createdAt)]
        )

        do {
            let targets = try modelContext.fetch(descriptor)
            if let first = targets.first {
                nutritionTarget = first
                return first
            }

            let target = NutritionTarget()
            modelContext.insert(target)
            try modelContext.save()
            nutritionTarget = target
            return target
        } catch {
            throw NutritionError.persistence("Could not load nutrition targets. Please try again.")
        }
    }

    func updateTarget(calories: Double, protein: Double, carbs: Double, fat: Double, enabled: Bool) throws {
        guard calories >= 0, protein >= 0, carbs >= 0, fat >= 0 else {
            throw NutritionError.validation("Targets cannot be negative.")
        }

        let target = try getOrCreateTarget()
        target.calorieTarget = calories
        target.proteinTarget = protein
        target.carbTarget = carbs
        target.fatTarget = fat
        target.isEnabled = enabled
        target.updatedAt = Date()

        do {
            try modelContext.save()
            nutritionTarget = target
        } catch {
            throw NutritionError.persistence("Could not save nutrition targets. Please try again.")
        }
    }

    @discardableResult
    func createMealTemplate(
        name: String,
        items: [MealInputItem],
        defaultCategory: FoodLogCategory = .other
    ) -> Meal? {
        guard let userId = try? requireUserId() else { return nil }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        let validItems = items.compactMap { item -> MealInputItem? in
            guard item.grams > 0 else { return nil }
            guard item.food.userId == userId else { return nil }
            return MealInputItem(food: item.food, grams: item.grams)
        }

        guard !validItems.isEmpty else { return nil }

        let meal = Meal(userId: userId, name: trimmedName, defaultCategory: defaultCategory)

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

    func fetchMeals(search: String? = nil) -> [Meal] {
        let query = search?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return meals
            .filter { meal in
                guard !query.isEmpty else { return true }
                return meal.name.localizedCaseInsensitiveContains(query)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func updateMeal(
        _ meal: Meal,
        name: String,
        items: [MealInputItem],
        defaultCategory: FoodLogCategory = .other
    ) -> Bool {
        guard let userId = try? requireUserId() else { return false }
        guard meal.userId == userId else { return false }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }

        let validItems = items.compactMap { item -> MealInputItem? in
            guard item.grams > 0 else { return nil }
            guard item.food.userId == userId else { return nil }
            return MealInputItem(food: item.food, grams: item.grams)
        }

        guard !validItems.isEmpty else { return false }

        meal.name = trimmedName
        meal.defaultCategory = defaultCategory
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
        guard let userId = try? requireUserId(), meal.userId == userId else { return }
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
        let userId = try requireUserId()
        try validateMealOwnership(template, expectedUserId: userId)

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
            try validateFoodOwnership(item.food, expectedUserId: userId)

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
            try validateFoodLogOwnership(log, expectedUserId: userId)
        }
        try validateMealEntryOwnership(mealEntry, expectedUserId: userId)

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
        let userId = try requireUserId()
        guard grams > 0 else {
            throw NutritionError.validation("Grams must be greater than 0.")
        }
        try validateFoodOwnership(food, expectedUserId: userId)

        let log = FoodLog(
            userId: userId,
            timestamp: timestamp,
            category: category,
            grams: grams,
            note: normalizedOptionalText(note),
            quickCaloriesKcal: nil,
            food: food,
            mealEntry: nil
        )

        modelContext.insert(log)
        try validateFoodLogOwnership(log, expectedUserId: userId)

        do {
            try modelContext.save()
            loadDayData(for: timestamp)
            loadFoods()
            return log
        } catch {
            throw NutritionError.persistence("Could not save this food log. Please try again.")
        }
    }

    func addQuickCaloriesLog(
        calories: Double,
        timestamp: Date,
        category: FoodLogCategory,
        note: String?
    ) throws -> FoodLog {
        guard calories > 0 else {
            throw NutritionError.validation("Calories must be greater than 0.")
        }
        let userId = try requireUserId()

        let quickFood = try getOrCreateQuickCaloriesFood()
        let log = FoodLog(
            userId: userId,
            timestamp: timestamp,
            category: category,
            grams: calories,
            note: normalizedOptionalText(note),
            quickCaloriesKcal: calories,
            food: quickFood,
            mealEntry: nil
        )

        modelContext.insert(log)
        try validateFoodLogOwnership(log, expectedUserId: userId)

        do {
            try modelContext.save()
            loadDayData(for: timestamp)
            loadFoods()
            return log
        } catch {
            throw NutritionError.persistence("Could not save quick calories. Please try again.")
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

    func copyStandaloneLogs(from sourceDate: Date, to targetDate: Date) throws -> Int {
        let userId = try requireUserId()

        let (sourceStart, sourceEnd) = dayRange(for: sourceDate)
        let descriptor = FetchDescriptor<FoodLog>(
            predicate: #Predicate<FoodLog> { log in
                log.userId == userId
                    && log.timestamp >= sourceStart
                    && log.timestamp < sourceEnd
                    && log.mealEntry == nil
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )

        do {
            let sourceLogs = try modelContext.fetch(descriptor)
            guard !sourceLogs.isEmpty else { return 0 }

            for sourceLog in sourceLogs {
                let targetTimestamp = dateByPinning(sourceLog.timestamp, to: targetDate)
                let newLog = FoodLog(
                    userId: userId,
                    timestamp: targetTimestamp,
                    category: sourceLog.category,
                    grams: sourceLog.grams,
                    note: sourceLog.note,
                    quickCaloriesKcal: sourceLog.quickCaloriesKcal,
                    food: sourceLog.food,
                    mealEntry: nil
                )
                try validateFoodOwnership(sourceLog.food, expectedUserId: userId)
                try validateFoodLogOwnership(newLog, expectedUserId: userId)
                modelContext.insert(newLog)
            }

            try modelContext.save()
            loadDayData(for: targetDate)
            loadFoods()
            return sourceLogs.count
        } catch {
            throw NutritionError.persistence("Could not copy yesterday's standalone logs. Please try again.")
        }
    }

    func createMealTemplate(from entry: MealEntry, name: String) throws -> Meal {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw NutritionError.validation("Template name is required.")
        }

        let items = entry.logs
            .sorted { $0.timestamp < $1.timestamp }
            .map { MealInputItem(food: $0.food, grams: $0.grams) }

        guard !items.isEmpty else {
            throw NutritionError.validation("This meal entry has no items to save.")
        }

        guard let meal = createMealTemplate(name: trimmedName, items: items, defaultCategory: entry.category) else {
            throw NutritionError.persistence("Could not save meal template. Please try again.")
        }
        return meal
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

    private func getOrCreateQuickCaloriesFood() throws -> Food {
        let userId = try requireUserId()

        if let existing = foods.first(where: { $0.userId == userId && $0.name == "Quick Calories" }) {
            return existing
        }

        let descriptor = FetchDescriptor<Food>(
            predicate: #Predicate<Food> { food in
                food.userId == userId && food.name == "Quick Calories"
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )

        do {
            if let existing = try modelContext.fetch(descriptor).first {
                try validateFoodOwnership(existing, expectedUserId: userId)
                return existing
            }

            let quickFood = Food(
                userId: userId,
                name: "Quick Calories",
                brand: nil,
                referenceLabel: "1 kcal",
                gramsPerReference: 1,
                kcalPerReference: 1,
                proteinPerReference: 0,
                carbPerReference: 0,
                fatPerReference: 0
            )

            modelContext.insert(quickFood)
            try modelContext.save()
            loadFoods()
            try validateFoodOwnership(quickFood, expectedUserId: userId)
            return quickFood
        } catch {
            throw NutritionError.persistence("Could not create quick calories helper food.")
        }
    }

    private func validateFoodOwnership(_ food: Food, expectedUserId: UUID) throws {
        guard food.userId == expectedUserId else {
            throw NutritionError.validation("Food ownership mismatch. Please re-create this food under your active account.")
        }
    }

    private func validateMealOwnership(_ meal: Meal, expectedUserId: UUID) throws {
        guard meal.userId == expectedUserId else {
            throw NutritionError.validation("Meal ownership mismatch. Please re-create this meal template under your active account.")
        }
    }

    private func validateMealEntryOwnership(_ entry: MealEntry, expectedUserId: UUID) throws {
        guard entry.userId == expectedUserId else {
            throw NutritionError.validation("Meal entry ownership mismatch.")
        }
        if let templateMeal = entry.templateMeal {
            try validateMealOwnership(templateMeal, expectedUserId: expectedUserId)
        }
    }

    private func validateFoodLogOwnership(_ log: FoodLog, expectedUserId: UUID) throws {
        guard log.userId == expectedUserId else {
            throw NutritionError.validation("Food log ownership mismatch.")
        }
        try validateFoodOwnership(log.food, expectedUserId: expectedUserId)
        if let mealEntry = log.mealEntry {
            try validateMealEntryOwnership(mealEntry, expectedUserId: expectedUserId)
        }
    }
}
