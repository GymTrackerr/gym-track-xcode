import Foundation
import SwiftUI
import SwiftData
import Combine

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
        let food: FoodItem
        let grams: Double
    }

    struct DailyKcalPoint: Identifiable {
        let date: Date
        let kcal: Double
        var id: Date { date }
    }

    enum NutritionSeriesMetric: String, CaseIterable, Identifiable {
        case calories
        case protein
        case carbs
        case fat

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .calories:
                return "Calories"
            case .protein:
                return "Protein"
            case .carbs:
                return "Carbs"
            case .fat:
                return "Fat"
            }
        }
    }

    struct DailyNutritionPoint: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    @Published var foods: [FoodItem] = []
    @Published var meals: [MealRecipe] = []
    @Published var dayLogs: [NutritionLogEntry] = []
    @Published var dayMealEntries: [NutritionLogEntry] = []
    @Published var nutritionTarget: NutritionTarget?
    @Published var nutrientDefinitions: [NutritionNutrientDefinition] = []
    private let repository: NutritionRepositoryProtocol

    init(context: ModelContext, repository: NutritionRepositoryProtocol) {
        self.repository = repository
        super.init(context: context)
    }

    override func loadFeature() {
        if let userId = currentUser?.id {
            do {
                try NutritionDataBackfillService(context: modelContext).backfill(userId: userId)
            } catch {
                print("Failed to backfill nutrition data: \(error)")
            }
        }
        loadFoods()
        loadMeals()
        loadNutrientDefinitions()
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

        do {
            foods = try repository.fetchFoodItems(for: userId)
        } catch {
            foods = []
            print("Failed to fetch foods: \(error)")
        }
    }

    func loadMeals() {
        guard let userId = currentUser?.id else {
            meals = []
            return
        }

        do {
            meals = try repository.fetchMealRecipes(for: userId)
        } catch {
            meals = []
            print("Failed to fetch meals: \(error)")
        }
    }

    func loadNutrientDefinitions() {
        guard let userId = currentUser?.id else {
            nutrientDefinitions = []
            return
        }

        do {
            let descriptor = FetchDescriptor<NutritionNutrientDefinition>(
                predicate: #Predicate<NutritionNutrientDefinition> { definition in
                    definition.userId == userId && definition.soft_deleted == false && definition.isArchived == false
                },
                sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.displayName)]
            )
            nutrientDefinitions = try modelContext.fetch(descriptor)
        } catch {
            nutrientDefinitions = []
            print("Failed to fetch nutrient definitions: \(error)")
        }
    }

    func visibleNutrientDefinitions() -> [NutritionNutrientDefinition] {
        nutrientDefinitions
            .filter { $0.isVisible && !$0.isArchived && !$0.soft_deleted }
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
                return $0.sortOrder < $1.sortOrder
            }
    }

    func fetchFoods(search: String? = nil, includeArchived: Bool = false, kind: FoodItemKind? = nil) -> [FoodItem] {
        let query = search?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return foods
            .filter { includeArchived || !$0.isArchived }
            .filter { item in
                guard let kind else { return true }
                return item.kind == kind
            }
            .filter { item in
                guard !query.isEmpty else { return true }
                return item.name.localizedCaseInsensitiveContains(query)
                    || (item.brand?.localizedCaseInsensitiveContains(query) ?? false)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func fetchFavoriteFoods(includeArchived: Bool = false, kind: FoodItemKind? = nil) -> [FoodItem] {
        fetchFoods(search: nil, includeArchived: includeArchived, kind: kind)
            .filter { $0.isFavorite }
    }

    func fetchRecentFoods(days: Int = 14, includeArchived: Bool = false, kind: FoodItemKind? = nil) -> [FoodItem] {
        guard let userId = currentUser?.id else { return [] }
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -max(days, 1), to: now) ?? now
        let foodLogTypeRaw = NutritionLogType.food.rawValue

        do {
            let logs = try repository.fetchNutritionLogs(
                for: userId,
                between: start,
                and: now.addingTimeInterval(1)
            )
            .filter { $0.logTypeRaw == foodLogTypeRaw }
            .sorted { $0.timestamp > $1.timestamp }
            var seen: Set<UUID> = []
            var ordered: [FoodItem] = []

            for log in logs {
                guard let sourceItemId = log.sourceItemId,
                      let food = foods.first(where: { $0.id == sourceItemId }) else { continue }
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
        extraNutrients: [String: Double]? = nil,
        providedNutrientKeys: Set<String>? = nil,
        servingQuantity: Double? = nil,
        servingUnitLabel: String? = nil,
        labelProfile: NutritionLabelProfile? = nil,
        kind: FoodItemKind = .food,
        unit: FoodItemUnit = .grams
    ) -> FoodItem? {
        guard let userId = try? requireUserId() else { return nil }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        guard gramsPerReference > 0 else { return nil }
        guard kcalPerReference >= 0, proteinPerReference >= 0, carbPerReference >= 0, fatPerReference >= 0 else {
            return nil
        }

        let food = FoodItem(
            userId: userId,
            name: trimmedName,
            brand: normalizedOptionalText(brand),
            referenceLabel: normalizedOptionalText(referenceLabel),
            referenceQuantity: gramsPerReference,
            servingQuantity: sanitizedPositive(servingQuantity),
            servingUnitLabel: normalizedOptionalText(servingUnitLabel),
            labelProfile: labelProfile,
            caloriesPerReference: kcalPerReference,
            proteinPerReference: proteinPerReference,
            carbsPerReference: carbPerReference,
            fatPerReference: fatPerReference,
            extraNutrients: normalizedExtraNutrients(extraNutrients),
            providedNutrientKeys: providedNutrientKeys,
            kind: kind,
            unit: unit
        )

        do {
            try repository.insertFoodItem(food)
            loadFoods()
            return food
        } catch {
            print("Failed to save food: \(error)")
            return nil
        }
    }

    func updateFood(
        _ food: FoodItem,
        name: String,
        brand: String?,
        referenceLabel: String?,
        gramsPerReference: Double,
        kcalPerReference: Double,
        proteinPerReference: Double,
        carbPerReference: Double,
        fatPerReference: Double,
        extraNutrients: [String: Double]? = nil,
        providedNutrientKeys: Set<String>? = nil,
        servingQuantity: Double? = nil,
        servingUnitLabel: String? = nil,
        labelProfile: NutritionLabelProfile? = nil,
        kind: FoodItemKind? = nil,
        unit: FoodItemUnit? = nil
    ) -> Bool {
        guard let userId = try? requireUserId() else { return false }
        guard food.userId == userId else { return false }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        guard gramsPerReference > 0 else { return false }
        guard kcalPerReference >= 0, proteinPerReference >= 0, carbPerReference >= 0, fatPerReference >= 0 else {
            return false
        }

        food.name = trimmedName
        food.brand = normalizedOptionalText(brand)
        food.referenceLabel = normalizedOptionalText(referenceLabel)
        food.referenceQuantity = gramsPerReference
        food.servingQuantity = sanitizedPositive(servingQuantity)
        food.servingUnitLabel = normalizedOptionalText(servingUnitLabel)
        food.labelProfile = labelProfile
        food.caloriesPerReference = kcalPerReference
        food.proteinPerReference = proteinPerReference
        food.carbsPerReference = carbPerReference
        food.fatPerReference = fatPerReference
        food.extraNutrients = normalizedExtraNutrients(extraNutrients)
        if let providedNutrientKeys {
            food.providedNutrientKeys = providedNutrientKeys
        }
        if let kind { food.kind = kind }
        if let unit { food.unit = unit }
        food.updatedAt = Date()

        do {
            try repository.saveFoodItem(food)
            loadFoods()
            return true
        } catch {
            print("Failed to update food: \(error)")
            return false
        }
    }

    func toggleFavorite(food: FoodItem) {
        food.isFavorite.toggle()
        food.updatedAt = Date()

        do {
            try repository.saveFoodItem(food)
            loadFoods()
        } catch {
            print("Failed to toggle favorite: \(error)")
        }
    }

    func archiveFood(food: FoodItem) throws {
        food.isArchived = true
        food.updatedAt = Date()

        do {
            try repository.saveFoodItem(food)
            loadFoods()
        } catch {
            throw NutritionError.persistence("Could not archive this food. Please try again.")
        }
    }

    func unarchiveFood(food: FoodItem) throws {
        food.isArchived = false
        food.updatedAt = Date()

        do {
            try repository.saveFoodItem(food)
            loadFoods()
        } catch {
            throw NutritionError.persistence("Could not unarchive this food. Please try again.")
        }
    }

    func fetchMeals(search: String? = nil) -> [MealRecipe] {
        let query = search?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return meals
            .filter { meal in
                guard !query.isEmpty else { return true }
                return meal.name.localizedCaseInsensitiveContains(query)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @discardableResult
    func createMealTemplate(
        name: String,
        items: [MealInputItem],
        defaultCategory: FoodLogCategory = .other,
        batchSize: Double = 1,
        servingUnitLabel: String? = nil
    ) -> MealRecipe? {
        guard let userId = try? requireUserId() else { return nil }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        let validItems = items.compactMap { item -> MealInputItem? in
            guard item.grams > 0 else { return nil }
            guard item.food.userId == userId else { return nil }
            return MealInputItem(food: item.food, grams: item.grams)
        }

        guard !validItems.isEmpty else { return nil }

        let meal = MealRecipe(
            userId: userId,
            name: trimmedName,
            batchSize: max(0.0001, batchSize),
            servingUnitLabel: normalizedOptionalText(servingUnitLabel) ?? "serving",
            defaultCategory: defaultCategory,
            cachedExtraNutrients: nil,
            isArchived: false
        )

        do {
            try repository.insertMealRecipe(meal)
            try repository.replaceMealRecipeItems(
                on: meal,
                with: validItems.map { (foodItem: $0.food, amount: $0.grams, amountUnit: $0.food.unit) }
            )
            loadMeals()
            return meal
        } catch {
            print("Failed to save meal: \(error)")
            return nil
        }
    }

    func updateMeal(
        _ meal: MealRecipe,
        name: String,
        items: [MealInputItem],
        defaultCategory: FoodLogCategory = .other,
        batchSize: Double = 1,
        servingUnitLabel: String? = nil
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
        meal.batchSize = max(0.0001, batchSize)
        meal.servingUnitLabel = normalizedOptionalText(servingUnitLabel) ?? "serving"
        meal.updatedAt = Date()

        do {
            try repository.replaceMealRecipeItems(
                on: meal,
                with: validItems.map { (foodItem: $0.food, amount: $0.grams, amountUnit: $0.food.unit) }
            )
            loadMeals()
            return true
        } catch {
            print("Failed to update meal: \(error)")
            return false
        }
    }

    func deleteMeal(_ meal: MealRecipe) {
        guard let userId = try? requireUserId(), meal.userId == userId else { return }

        do {
            try repository.softDeleteMealRecipe(meal)
            loadMeals()
        } catch {
            print("Failed to delete meal: \(error)")
        }
    }

    @discardableResult
    func addFoodLog(
        food: FoodItem,
        grams: Double,
        timestamp: Date,
        category: FoodLogCategory,
        note: String?,
        amountMode: NutritionLogAmountMode = .baseUnit,
        servingCount: Double? = nil
    ) throws -> NutritionLogEntry {
        let draft = try buildFoodLogDraft(
            food: food,
            amount: grams,
            timestamp: timestamp,
            category: category,
            note: note,
            amountMode: amountMode,
            servingCount: servingCount
        )
        return try createNutritionLogEntry(from: draft)
    }

    @discardableResult
    func logMeal(
        template: MealRecipe,
        amount: Double = 1,
        timestamp: Date,
        category: FoodLogCategory,
        note: String?
    ) throws -> NutritionLogEntry {
        let draft = try buildMealLogDraft(
            meal: template,
            amount: amount,
            timestamp: timestamp,
            category: category,
            note: note
        )
        return try createNutritionLogEntry(from: draft)
    }

    @discardableResult
    func addQuickCaloriesLog(
        calories: Double,
        timestamp: Date,
        category: FoodLogCategory,
        note: String?
    ) throws -> NutritionLogEntry {
        try addQuickNutritionLog(
            calories: calories,
            protein: nil,
            carbs: nil,
            fat: nil,
            timestamp: timestamp,
            category: category,
            note: note
        )
    }

    @discardableResult
    func addQuickNutritionLog(
        calories: Double?,
        protein: Double?,
        carbs: Double?,
        fat: Double?,
        extraNutrients: [String: Double]? = nil,
        timestamp: Date,
        category: FoodLogCategory,
        note: String?
    ) throws -> NutritionLogEntry {
        let draft = try buildQuickEntryDraft(
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            extraNutrients: extraNutrients,
            timestamp: timestamp,
            category: category,
            note: note
        )
        return try createNutritionLogEntry(from: draft)
    }

    func updateFoodLog(
        _ log: NutritionLogEntry,
        amount: Double,
        timestamp: Date,
        category: FoodLogCategory,
        note: String?
    ) -> Bool {
        guard log.logType == .quickCalories || amount > 0 else { return false }
        let previousAmount = log.amount

        log.amount = amount
        log.timestamp = timestamp
        log.category = category
        log.note = normalizedOptionalText(note)
        switch log.logType {
        case .quickCalories:
            if log.hasProvidedNutrient(NutritionNutrientKey.calories) {
                log.caloriesSnapshot = max(0, amount)
            }
        case .food, .meal:
            let ratio: Double
            if previousAmount > 0 {
                ratio = amount / previousAmount
            } else {
                ratio = 1
            }
            // Scale parent snapshots only. Keep recipeItemsSnapshot immutable.
            log.caloriesSnapshot = max(0, log.caloriesSnapshot * ratio)
            log.proteinSnapshot = max(0, log.proteinSnapshot * ratio)
            log.carbsSnapshot = max(0, log.carbsSnapshot * ratio)
            log.fatSnapshot = max(0, log.fatSnapshot * ratio)
            if let extraNutrients = log.extraNutrientsSnapshot {
                log.extraNutrientsSnapshot = extraNutrients.mapValues { max(0, $0 * ratio) }
            }
            if log.amountMode == .serving, let previousServingCount = log.servingCountSnapshot, previousServingCount > 0 {
                log.servingCountSnapshot = max(0, previousServingCount * ratio)
            }
        }
        updateLogDateMetadata(log)
        log.updatedAt = Date()

        do {
            try repository.saveNutritionLogEntry(log)
            loadDayData(for: timestamp)
            return true
        } catch {
            print("Failed to update food log: \(error)")
            return false
        }
    }

    func deleteFoodLog(_ log: NutritionLogEntry, selectedDate: Date) {
        do {
            try repository.softDeleteNutritionLogEntry(log)
            loadDayData(for: selectedDate)
            loadFoods()
        } catch {
            print("Failed to delete food log: \(error)")
        }
    }

    func deleteMealEntry(_ entry: NutritionLogEntry, selectedDate: Date) {
        do {
            try repository.softDeleteNutritionLogEntry(entry)
            loadDayData(for: selectedDate)
            loadFoods()
        } catch {
            print("Failed to delete meal entry: \(error)")
        }
    }

    func loadDayData(for selectedDate: Date) {
        guard let userId = currentUser?.id else {
            dayLogs = []
            dayMealEntries = []
            return
        }

        let (dayStart, dayEnd) = dayRange(for: selectedDate)

        do {
            let logs = try repository.fetchNutritionLogs(for: userId, between: dayStart, and: dayEnd)
            dayLogs = logs.sorted { $0.timestamp < $1.timestamp }
            dayMealEntries = dayLogs.filter { $0.logType == .meal }
        } catch {
            dayLogs = []
            dayMealEntries = []
            print("Failed to fetch day logs: \(error)")
        }
    }

    func copyStandaloneLogs(from sourceDate: Date, to targetDate: Date) throws -> Int {
        let userId = try requireUserId()
        let mealLogTypeRaw = NutritionLogType.meal.rawValue

        let (sourceStart, sourceEnd) = dayRange(for: sourceDate)
        do {
            let sourceLogs = try repository.fetchNutritionLogs(for: userId, between: sourceStart, and: sourceEnd)
                .filter { $0.logTypeRaw != mealLogTypeRaw }
            guard !sourceLogs.isEmpty else { return 0 }

            for sourceLog in sourceLogs {
                let targetTimestamp = dateByPinning(sourceLog.timestamp, to: targetDate)
                let draft = NutritionLogDraft(
                    logType: sourceLog.logType,
                    creationMethod: .manual,
                    sourceItemId: sourceLog.sourceItemId,
                    sourceMealId: sourceLog.sourceMealId,
                    nameSnapshot: sourceLog.nameSnapshot,
                    brandSnapshot: sourceLog.brandSnapshot,
                    amount: sourceLog.amount,
                    amountUnitSnapshot: sourceLog.amountUnitSnapshot,
                    servingUnitLabelSnapshot: sourceLog.servingUnitLabelSnapshot,
                    amountMode: sourceLog.amountMode,
                    servingQuantitySnapshot: sourceLog.servingQuantitySnapshot,
                    servingCountSnapshot: sourceLog.servingCountSnapshot,
                    caloriesSnapshot: sourceLog.caloriesSnapshot,
                    proteinSnapshot: sourceLog.proteinSnapshot,
                    carbsSnapshot: sourceLog.carbsSnapshot,
                    fatSnapshot: sourceLog.fatSnapshot,
                    extraNutrientsSnapshot: sourceLog.extraNutrientsSnapshot,
                    recipeItemsSnapshot: sourceLog.recipeItemsSnapshot,
                    providedNutrientKeys: sourceLog.providedNutrientKeys,
                    timestamp: targetTimestamp,
                    category: sourceLog.category,
                    note: sourceLog.note
                )
                let newLog = createNutritionLogEntry(from: draft, userId: userId)
                try repository.insertNutritionLogEntry(newLog)
            }
            loadDayData(for: targetDate)
            loadFoods()
            return sourceLogs.count
        } catch {
            throw NutritionError.persistence("Could not copy yesterday's standalone logs. Please try again.")
        }
    }

    func createMealTemplate(from entry: NutritionLogEntry, name: String) throws -> MealRecipe {
        guard entry.logType == .meal else {
            throw NutritionError.validation("Only meal logs can be saved as a template.")
        }

        let sourceMeal = entry.sourceMealId.flatMap { id in meals.first(where: { $0.id == id }) }
        let fallbackName = entry.nameSnapshot
        let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackName : name

        if let sourceMeal {
            let copiedItems = sourceMeal.items
                .sorted { $0.order < $1.order }
                .map { item in
                    MealInputItem(food: item.foodItem, grams: item.amount)
                }
            if let created = createMealTemplate(
                name: finalName,
                items: copiedItems,
                defaultCategory: sourceMeal.defaultCategory,
                batchSize: sourceMeal.batchSize,
                servingUnitLabel: sourceMeal.servingUnitLabel
            ) {
                return created
            }
        }

        throw NutritionError.validation("Unable to create template from this meal log.")
    }

    func totalKcal(for logs: [NutritionLogEntry]) -> Double {
        logs.reduce(0) { partial, log in
            partial + (log.hasProvidedNutrient(NutritionNutrientKey.calories) ? log.caloriesSnapshot : 0)
        }
    }

    func totalProtein(for logs: [NutritionLogEntry]) -> Double {
        logs.reduce(0) { partial, log in
            partial + (log.hasProvidedNutrient(NutritionNutrientKey.protein) ? log.proteinSnapshot : 0)
        }
    }

    func totalCarbs(for logs: [NutritionLogEntry]) -> Double {
        logs.reduce(0) { partial, log in
            partial + (log.hasProvidedNutrient(NutritionNutrientKey.carbs) ? log.carbsSnapshot : 0)
        }
    }

    func totalFat(for logs: [NutritionLogEntry]) -> Double {
        logs.reduce(0) { partial, log in
            partial + (log.hasProvidedNutrient(NutritionNutrientKey.fat) ? log.fatSnapshot : 0)
        }
    }

    func totalOptionalNutrient(name: String, for logs: [NutritionLogEntry]) -> Double {
        logs.reduce(0) { partial, log in
            let key = NutritionNutrientKey.normalized(name)
            return partial + (log.hasProvidedNutrient(key) ? (log.extraNutrientsSnapshot?[key] ?? 0) : 0)
        }
    }

    func dailyCaloriesSeries(endingOn endDate: Date, days: Int = 7) throws -> [DailyKcalPoint] {
        let points = try dailyNutritionSeries(endingOn: endDate, days: days, metric: .calories)
        return points.map { DailyKcalPoint(date: $0.date, kcal: $0.value) }
    }

    func calorieIntake(for day: Date) throws -> Double {
        try dailyNutritionSeries(endingOn: day, days: 1, metric: .calories).first?.value ?? 0
    }

    func calorieIntakeSeries(endingOn endDate: Date, days: Int = 7) throws -> [DailyKcalPoint] {
        try dailyCaloriesSeries(endingOn: endDate, days: days)
    }

    func dailyNutritionSeries(
        endingOn endDate: Date,
        days: Int = 7,
        metric: NutritionSeriesMetric
    ) throws -> [DailyNutritionPoint] {
        let userId = try requireUserId()
        let calendar = Calendar.current
        let clampedDays = max(days, 1)
        let endDayStart = calendar.startOfDay(for: endDate)
        let startDay = calendar.date(byAdding: .day, value: -(clampedDays - 1), to: endDayStart) ?? endDayStart
        let rangeEnd = calendar.date(byAdding: .day, value: 1, to: endDayStart) ?? endDayStart

        let fetchedLogs: [NutritionLogEntry]
        do {
            fetchedLogs = try repository.fetchNutritionLogs(for: userId, between: startDay, and: rangeEnd)
        } catch {
            throw NutritionError.persistence("Could not load nutrition series data.")
        }

        let groupedByDay = Dictionary(grouping: fetchedLogs) { log in
            calendar.startOfDay(for: log.timestamp)
        }

        return (0..<clampedDays).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: startDay) ?? startDay
            let dayLogs = groupedByDay[date] ?? []
            let value: Double = dayLogs.reduce(0) { partial, log in
                partial + metricValue(for: log, metric: metric)
            }
            return DailyNutritionPoint(date: date, value: value)
        }
    }

    func logsInDateInterval(_ interval: DateInterval) throws -> [NutritionLogEntry] {
        let userId = try requireUserId()

        do {
            return try repository.fetchNutritionLogs(for: userId, in: interval)
        } catch {
            throw NutritionError.persistence("Could not load nutrition logs for this timeframe.")
        }
    }

    func snapshotHistory(for food: FoodItem, limit: Int = 20) -> [NutritionLogEntry] {
        guard let userId = currentUser?.id else { return [] }
        do {
            let bounds = try repository.fetchNutritionLogBounds(for: userId)
            guard let oldest = bounds.oldest, let newest = bounds.newest else { return [] }
            let end = newest.addingTimeInterval(1)
            return try repository.fetchNutritionLogs(for: userId, between: oldest, and: end)
                .filter { $0.sourceItemId == food.id }
                .sorted { $0.timestamp > $1.timestamp }
                .prefix(max(limit, 1))
                .map { $0 }
        } catch {
            print("Failed to load food snapshot history: \(error)")
            return []
        }
    }

    func snapshotHistory(for meal: MealRecipe, limit: Int = 20) -> [NutritionLogEntry] {
        guard let userId = currentUser?.id else { return [] }
        do {
            let bounds = try repository.fetchNutritionLogBounds(for: userId)
            guard let oldest = bounds.oldest, let newest = bounds.newest else { return [] }
            let end = newest.addingTimeInterval(1)
            return try repository.fetchNutritionLogs(for: userId, between: oldest, and: end)
                .filter { $0.sourceMealId == meal.id }
                .sorted { $0.timestamp > $1.timestamp }
                .prefix(max(limit, 1))
                .map { $0 }
        } catch {
            print("Failed to load meal snapshot history: \(error)")
            return []
        }
    }

    func nutritionBounds(for metric: NutritionSeriesMetric) throws -> (oldest: Date?, newest: Date?) {
        let userId = try requireUserId()
        _ = metric
        do {
            return try repository.fetchNutritionLogBounds(for: userId)
        } catch {
            throw NutritionError.persistence("Could not load nutrition bounds.")
        }
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

    func getOrCreateTarget() throws -> NutritionTarget {
        let currentUserId = currentUser?.id
        do {
            let targets = try repository.fetchTargets()
            if let currentUserId {
                if let scoped = targets.first(where: { $0.userId == currentUserId }) {
                    nutritionTarget = scoped
                    return scoped
                }
            } else if let first = targets.first {
                nutritionTarget = first
                return first
            }

            let target = NutritionTarget(userId: currentUserId)
            try repository.insertNutritionTarget(target)
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
            try repository.saveNutritionTarget(target)
            nutritionTarget = target
        } catch {
            throw NutritionError.persistence("Could not save nutrition targets. Please try again.")
        }
    }

    func updateLabelProfile(_ profile: NutritionLabelProfile) throws {
        let target = try getOrCreateTarget()
        target.labelProfile = profile
        target.updatedAt = Date()

        do {
            try repository.saveNutritionTarget(target)
            nutritionTarget = target
        } catch {
            throw NutritionError.persistence("Could not save nutrition label style. Please try again.")
        }
    }

    func buildFoodLogDraft(
        food: FoodItem,
        amount: Double,
        timestamp: Date,
        category: FoodLogCategory,
        note: String?,
        amountMode: NutritionLogAmountMode = .baseUnit,
        servingCount: Double? = nil
    ) throws -> NutritionLogDraft {
        let userId = try requireUserId()
        guard food.userId == userId else {
            throw NutritionError.validation("Food ownership mismatch.")
        }
        guard amount > 0 else {
            throw NutritionError.validation("Amount must be greater than 0.")
        }

        let factor = amount / max(food.referenceQuantity, 0.0001)
        let servingQuantitySnapshot = amountMode == .serving ? food.servingQuantity : nil
        let servingUnitLabelSnapshot = amountMode == .serving ? normalizedOptionalText(food.servingUnitLabel) : nil
        return NutritionLogDraft(
            logType: .food,
            creationMethod: .foodItem,
            sourceItemId: food.id,
            sourceMealId: nil,
            nameSnapshot: food.name,
            brandSnapshot: food.brand,
            amount: amount,
            amountUnitSnapshot: food.unit.shortLabel,
            servingUnitLabelSnapshot: servingUnitLabelSnapshot,
            amountMode: amountMode,
            servingQuantitySnapshot: servingQuantitySnapshot,
            servingCountSnapshot: amountMode == .serving ? sanitizedPositive(servingCount) : nil,
            caloriesSnapshot: max(0, food.caloriesPerReference * factor),
            proteinSnapshot: max(0, food.proteinPerReference * factor),
            carbsSnapshot: max(0, food.carbsPerReference * factor),
            fatSnapshot: max(0, food.fatPerReference * factor),
            extraNutrientsSnapshot: scaledExtraNutrients(food.extraNutrients, by: factor),
            recipeItemsSnapshot: nil,
            providedNutrientKeys: food.providedNutrientKeys,
            timestamp: timestamp,
            category: category,
            note: note
        )
    }

    func buildMealLogDraft(
        meal: MealRecipe,
        amount: Double,
        timestamp: Date,
        category: FoodLogCategory,
        note: String?
    ) throws -> NutritionLogDraft {
        let userId = try requireUserId()
        guard meal.userId == userId else {
            throw NutritionError.validation("Meal ownership mismatch.")
        }
        guard amount > 0 else {
            throw NutritionError.validation("Amount must be greater than 0.")
        }

        let perServing = calculateRecipePerServingNutrition(meal)
        let recipeItems = calculateRecipeItemsSnapshot(meal)

        return NutritionLogDraft(
            logType: .meal,
            creationMethod: .mealRecipe,
            sourceItemId: nil,
            sourceMealId: meal.id,
            nameSnapshot: meal.name,
            brandSnapshot: nil,
            amount: amount,
            amountUnitSnapshot: normalizedOptionalText(meal.servingUnitLabel) ?? "serving",
            servingUnitLabelSnapshot: normalizedOptionalText(meal.servingUnitLabel),
            amountMode: .serving,
            servingQuantitySnapshot: nil,
            servingCountSnapshot: amount,
            caloriesSnapshot: max(0, perServing.calories * amount),
            proteinSnapshot: max(0, perServing.protein * amount),
            carbsSnapshot: max(0, perServing.carbs * amount),
            fatSnapshot: max(0, perServing.fat * amount),
            extraNutrientsSnapshot: scaledExtraNutrients(perServing.extraNutrients, by: amount),
            recipeItemsSnapshot: recipeItems,
            providedNutrientKeys: NutritionNutrientKey.coreKeySet,
            timestamp: timestamp,
            category: category,
            note: note
        )
    }

    func buildQuickEntryDraft(
        calories: Double?,
        protein: Double?,
        carbs: Double?,
        fat: Double?,
        extraNutrients: [String: Double]? = nil,
        timestamp: Date,
        category: FoodLogCategory,
        note: String?
    ) throws -> NutritionLogDraft {
        let provided = providedKeys(
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            extraNutrients: extraNutrients
        )
        guard !provided.isEmpty else {
            throw NutritionError.validation("Add at least one nutrition value before saving.")
        }
        guard [calories, protein, carbs, fat].allSatisfy({ ($0 ?? 0) >= 0 }) else {
            throw NutritionError.validation("Nutrition values cannot be negative.")
        }

        return NutritionLogDraft(
            logType: .quickCalories,
            creationMethod: .quickEntry,
            sourceItemId: nil,
            sourceMealId: nil,
            nameSnapshot: "Quick Entry",
            brandSnapshot: nil,
            amount: max(0, calories ?? 0),
            amountUnitSnapshot: "entry",
            servingUnitLabelSnapshot: nil,
            amountMode: .quickAdd,
            servingQuantitySnapshot: nil,
            servingCountSnapshot: nil,
            caloriesSnapshot: max(0, calories ?? 0),
            proteinSnapshot: max(0, protein ?? 0),
            carbsSnapshot: max(0, carbs ?? 0),
            fatSnapshot: max(0, fat ?? 0),
            extraNutrientsSnapshot: normalizedExtraNutrients(extraNutrients),
            recipeItemsSnapshot: nil,
            providedNutrientKeys: provided,
            timestamp: timestamp,
            category: category,
            note: note
        )
    }

    func buildImportedLogDraft(
        logType: NutritionLogType,
        sourceItemId: UUID?,
        sourceMealId: UUID?,
        nameSnapshot: String,
        brandSnapshot: String?,
        amount: Double,
        amountUnitSnapshot: String,
        servingUnitLabelSnapshot: String?,
        amountMode: NutritionLogAmountMode? = nil,
        servingQuantitySnapshot: Double? = nil,
        servingCountSnapshot: Double? = nil,
        caloriesSnapshot: Double,
        proteinSnapshot: Double,
        carbsSnapshot: Double,
        fatSnapshot: Double,
        extraNutrientsSnapshot: [String: Double]?,
        recipeItemsSnapshot: [RecipeItemSnapshot]?,
        providedNutrientKeys: Set<String>? = nil,
        timestamp: Date,
        category: FoodLogCategory,
        note: String?,
        creationMethod: LogCreationMethod
    ) -> NutritionLogDraft {
        NutritionLogDraft(
            logType: logType,
            creationMethod: creationMethod,
            sourceItemId: sourceItemId,
            sourceMealId: sourceMealId,
            nameSnapshot: nameSnapshot,
            brandSnapshot: brandSnapshot,
            amount: amount,
            amountUnitSnapshot: amountUnitSnapshot,
            servingUnitLabelSnapshot: servingUnitLabelSnapshot,
            amountMode: amountMode ?? defaultAmountMode(for: logType),
            servingQuantitySnapshot: servingQuantitySnapshot,
            servingCountSnapshot: servingCountSnapshot,
            caloriesSnapshot: max(0, caloriesSnapshot),
            proteinSnapshot: max(0, proteinSnapshot),
            carbsSnapshot: max(0, carbsSnapshot),
            fatSnapshot: max(0, fatSnapshot),
            extraNutrientsSnapshot: extraNutrientsSnapshot,
            recipeItemsSnapshot: recipeItemsSnapshot,
            providedNutrientKeys: providedNutrientKeys ?? NutritionNutrientKey.coreKeySet,
            timestamp: timestamp,
            category: category,
            note: note
        )
    }

    @discardableResult
    func createNutritionLogEntry(from draft: NutritionLogDraft) throws -> NutritionLogEntry {
        let userId = try requireUserId()
        try validateDraft(draft)

        let entry = createNutritionLogEntry(from: draft, userId: userId)

        do {
            try repository.insertNutritionLogEntry(entry)
            loadDayData(for: draft.timestamp)
            loadFoods()
            loadMeals()
            return entry
        } catch {
            throw NutritionError.persistence("Could not save nutrition log entry. Please try again.")
        }
    }

    func calculateRecipePerServingNutrition(_ meal: MealRecipe) -> NutritionFacts {
        let sortedItems = meal.items.sorted { $0.order < $1.order }
        guard !sortedItems.isEmpty else { return .zero }

        var calories: Double = 0
        var protein: Double = 0
        var carbs: Double = 0
        var fat: Double = 0
        var extraNutrients: [String: Double] = [:]

        for item in sortedItems {
            let food = item.foodItem
            let factor = item.amount / max(food.referenceQuantity, 0.0001)
            calories += max(0, food.caloriesPerReference * factor)
            protein += max(0, food.proteinPerReference * factor)
            carbs += max(0, food.carbsPerReference * factor)
            fat += max(0, food.fatPerReference * factor)

            if let foodExtra = food.extraNutrients {
                for (key, value) in foodExtra {
                    let normalizedKey = NutritionNutrientKey.normalized(key)
                    guard !normalizedKey.isEmpty else { continue }
                    extraNutrients[normalizedKey, default: 0] += max(0, value * factor)
                }
            }
        }

        let servingCount = max(meal.batchSize, 0.0001)
        let perServingExtras: [String: Double]? = extraNutrients.isEmpty
            ? nil
            : extraNutrients.mapValues { $0 / servingCount }

        return NutritionFacts(
            calories: calories / servingCount,
            protein: protein / servingCount,
            carbs: carbs / servingCount,
            fat: fat / servingCount,
            extraNutrients: perServingExtras
        )
    }

    func calculateRecipeItemsSnapshot(_ meal: MealRecipe) -> [RecipeItemSnapshot] {
        meal.items
            .sorted { $0.order < $1.order }
            .map { item in
                let food = item.foodItem
                let factor = item.amount / max(food.referenceQuantity, 0.0001)
                return RecipeItemSnapshot(
                    name: food.name,
                    amount: item.amount,
                    amountUnit: food.unit.shortLabel,
                    caloriesSnapshot: max(0, food.caloriesPerReference * factor),
                    proteinSnapshot: max(0, food.proteinPerReference * factor),
                    carbsSnapshot: max(0, food.carbsPerReference * factor),
                    fatSnapshot: max(0, food.fatPerReference * factor),
                    extraNutrientsSnapshot: scaledExtraNutrients(food.extraNutrients, by: factor)
                )
            }
    }

    func computeDayKey(timestamp: Date, userTimeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = userTimeZone
        let components = calendar.dateComponents([.year, .month, .day], from: timestamp)
        return String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
    }

    func computeLogDate(timestamp: Date, userTimeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = userTimeZone
        return calendar.startOfDay(for: timestamp)
    }

    func updateLogDateMetadata(_ log: NutritionLogEntry, userTimeZone: TimeZone = .current) {
        log.dayKey = computeDayKey(timestamp: log.timestamp, userTimeZone: userTimeZone)
        log.logDate = computeLogDate(timestamp: log.timestamp, userTimeZone: userTimeZone)
    }

    private func dayRange(for selectedDate: Date) -> (Date, Date) {
        let dayStart = Calendar.current.startOfDay(for: selectedDate)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return (dayStart, dayEnd)
    }

    private func metricValue(for log: NutritionLogEntry, metric: NutritionSeriesMetric) -> Double {
        switch metric {
        case .calories:
            return log.hasProvidedNutrient(NutritionNutrientKey.calories) ? log.caloriesSnapshot : 0
        case .protein:
            return log.hasProvidedNutrient(NutritionNutrientKey.protein) ? log.proteinSnapshot : 0
        case .carbs:
            return log.hasProvidedNutrient(NutritionNutrientKey.carbs) ? log.carbsSnapshot : 0
        case .fat:
            return log.hasProvidedNutrient(NutritionNutrientKey.fat) ? log.fatSnapshot : 0
        }
    }

    private func scaledExtraNutrients(_ input: [String: Double]?, by factor: Double) -> [String: Double]? {
        guard let input else { return nil }
        if input.isEmpty { return nil }
        return input.reduce(into: [String: Double]()) { partial, pair in
            let key = NutritionNutrientKey.normalized(pair.key)
            guard !key.isEmpty else { return }
            partial[key] = max(0, pair.value * factor)
        }
    }

    private func providedKeys(
        calories: Double?,
        protein: Double?,
        carbs: Double?,
        fat: Double?,
        extraNutrients: [String: Double]? = nil
    ) -> Set<String> {
        var keys: Set<String> = []
        if calories != nil { keys.insert(NutritionNutrientKey.calories) }
        if protein != nil { keys.insert(NutritionNutrientKey.protein) }
        if carbs != nil { keys.insert(NutritionNutrientKey.carbs) }
        if fat != nil { keys.insert(NutritionNutrientKey.fat) }
        for key in (extraNutrients ?? [:]).keys {
            keys.insert(NutritionNutrientKey.normalized(key))
        }
        return keys
    }

    private func normalizedExtraNutrients(_ values: [String: Double]?) -> [String: Double]? {
        guard let values else { return nil }
        let normalized = values.reduce(into: [String: Double]()) { partial, pair in
            let key = NutritionNutrientKey.normalized(pair.key)
            guard !key.isEmpty else { return }
            partial[key] = max(0, pair.value)
        }
        return normalized.isEmpty ? nil : normalized
    }

    private func sanitizedPositive(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private func defaultAmountMode(for logType: NutritionLogType) -> NutritionLogAmountMode {
        switch logType {
        case .food:
            return .baseUnit
        case .meal:
            return .serving
        case .quickCalories:
            return .quickAdd
        }
    }

    private func normalizedOptionalText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func validateDraft(_ draft: NutritionLogDraft) throws {
        if draft.nameSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw NutritionError.validation("Log name is required.")
        }
        if draft.logType != .quickCalories && draft.amount <= 0 {
            throw NutritionError.validation("Amount must be greater than 0.")
        }
        if draft.logType == .quickCalories && draft.providedNutrientKeys.isEmpty {
            throw NutritionError.validation("Add at least one nutrition value before saving.")
        }
        if draft.amountUnitSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw NutritionError.validation("Amount unit is required.")
        }
        if draft.caloriesSnapshot < 0 || draft.proteinSnapshot < 0 || draft.carbsSnapshot < 0 || draft.fatSnapshot < 0 {
            throw NutritionError.validation("Macro snapshots cannot be negative.")
        }
        if draft.logType != .meal, draft.recipeItemsSnapshot != nil {
            throw NutritionError.validation("Only meal logs can include recipe item snapshots.")
        }
    }

    private func createNutritionLogEntry(from draft: NutritionLogDraft, userId: UUID) -> NutritionLogEntry {
        let entry = NutritionLogEntry(
            userId: userId,
            timestamp: draft.timestamp,
            logType: draft.logType,
            sourceItemId: draft.sourceItemId,
            sourceMealId: draft.sourceMealId,
            amount: draft.amount,
            amountUnitSnapshot: draft.amountUnitSnapshot,
            category: draft.category,
            note: normalizedOptionalText(draft.note),
            dayKey: computeDayKey(timestamp: draft.timestamp),
            logDate: computeLogDate(timestamp: draft.timestamp),
            creationMethod: draft.creationMethod,
            nameSnapshot: draft.nameSnapshot,
            brandSnapshot: normalizedOptionalText(draft.brandSnapshot),
            servingUnitLabelSnapshot: normalizedOptionalText(draft.servingUnitLabelSnapshot),
            amountMode: draft.amountMode,
            servingQuantitySnapshot: draft.servingQuantitySnapshot,
            servingCountSnapshot: draft.servingCountSnapshot,
            caloriesSnapshot: max(0, draft.caloriesSnapshot),
            proteinSnapshot: max(0, draft.proteinSnapshot),
            carbsSnapshot: max(0, draft.carbsSnapshot),
            fatSnapshot: max(0, draft.fatSnapshot),
            extraNutrientsSnapshot: draft.extraNutrientsSnapshot,
            recipeItemsSnapshot: draft.recipeItemsSnapshot,
            providedNutrientKeys: draft.providedNutrientKeys
        )
        return entry
    }
}
