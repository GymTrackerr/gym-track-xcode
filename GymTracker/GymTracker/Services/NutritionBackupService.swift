import Foundation
import SwiftData

@MainActor
final class NutritionBackupService {
    enum BackupError: LocalizedError {
        case missingUser
        case invalidSchemaVersion(Int)
        case userMismatch
        case invalidBackup(String)
        case persistence(String)

        var errorDescription: String? {
            switch self {
            case .missingUser:
                return "You must be signed in to use nutrition backup."
            case .invalidSchemaVersion(let version):
                return "Unsupported backup schema version: \(version)."
            case .userMismatch:
                return "Backup user does not match the active account."
            case .invalidBackup(let message):
                return message
            case .persistence(let message):
                return message
            }
        }
    }

    struct ImportResult {
        let foods: Int
        let meals: Int
        let mealItems: Int
        let mealEntries: Int
        let foodLogs: Int
        let targets: Int
    }

    private let modelContext: ModelContext
    private let currentUserProvider: () -> User?

    init(context: ModelContext, currentUserProvider: @escaping () -> User?) {
        self.modelContext = context
        self.currentUserProvider = currentUserProvider
    }

    func exportNutritionJSON() throws -> URL {
        guard let userId = currentUserProvider()?.id else {
            throw BackupError.missingUser
        }

        let foods = try fetchFoods(userId: userId)
        let meals = try fetchMeals(userId: userId)
        let mealEntries = try fetchMealEntries(userId: userId)
        let foodLogs = try fetchFoodLogs(userId: userId)
        let mealItems = meals
            .flatMap { $0.items }
            .sorted { lhs, rhs in
                if lhs.meal?.id == rhs.meal?.id {
                    return lhs.order < rhs.order
                }
                return (lhs.meal?.id.uuidString ?? "") < (rhs.meal?.id.uuidString ?? "")
            }
        let targets = try fetchTargets()

        let payload = NutritionBackupPayload(
            schemaVersion: 1,
            exportedAt: Date(),
            userId: userId,
            foods: foods.map(FoodBackupDTO.init),
            meals: meals.map(MealBackupDTO.init),
            mealItems: mealItems.map(MealItemBackupDTO.init),
            mealEntries: mealEntries.map(MealEntryBackupDTO.init),
            foodLogs: foodLogs.map(FoodLogBackupDTO.init),
            nutritionTargets: targets.map(NutritionTargetBackupDTO.init)
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(payload)
            let fileURL = backupURL()
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            throw BackupError.persistence("Could not write nutrition backup file.")
        }
    }

    func importNutritionJSON(from url: URL) throws -> ImportResult {
        guard let userId = currentUserProvider()?.id else {
            throw BackupError.missingUser
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BackupError.persistence("Could not read backup file.")
        }

        let payload: NutritionBackupPayload
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            payload = try decoder.decode(NutritionBackupPayload.self, from: data)
        } catch {
            throw BackupError.invalidBackup("Backup file format is invalid.")
        }

        guard payload.schemaVersion == 1 else {
            throw BackupError.invalidSchemaVersion(payload.schemaVersion)
        }

        // Allow restore into a different account by remapping imported ownership
        // to the currently active user.

        do {
            // All upsert maps are scoped to current user to prevent cross-user mutation on ID collisions.
            var foodsById = mapFoodsById(try fetchFoods(userId: userId))
            var mealsById = mapMealsById(try fetchMeals(userId: userId))
            var entriesById = mapMealEntriesById(try fetchMealEntries(userId: userId))
            var logsById = mapFoodLogsById(try fetchFoodLogs(userId: userId))
            let allMealItems = try modelContext.fetch(FetchDescriptor<MealItem>())
            var mealItemsById: [UUID: MealItem] = [:]
            for item in allMealItems where item.meal?.userId == userId {
                if mealItemsById[item.id] != nil {
                    print("Duplicate meal item id detected for current user during import: \(item.id)")
                    continue
                }
                mealItemsById[item.id] = item
            }
            var targetsById = mapTargetsById(try fetchTargets())

            for dto in payload.foods {
                let food: Food
                if let existing = foodsById[dto.id] {
                    food = existing
                } else {
                    food = Food(
                        userId: userId,
                        name: dto.name,
                        brand: dto.brand,
                        referenceLabel: dto.referenceLabel,
                        gramsPerReference: dto.gramsPerReference,
                        kcalPerReference: dto.kcalPerReference,
                        proteinPerReference: dto.proteinPerReference,
                        carbPerReference: dto.carbPerReference,
                        fatPerReference: dto.fatPerReference,
                        isArchived: dto.isArchived,
                        isFavorite: dto.isFavorite,
                        kind: FoodKind(rawValue: dto.kindRaw) ?? .food,
                        unit: FoodUnit(rawValue: dto.unitRaw) ?? .grams
                    )
                    food.id = dto.id
                    modelContext.insert(food)
                    foodsById[dto.id] = food
                }

                food.userId = userId
                food.name = dto.name
                food.brand = dto.brand
                food.referenceLabel = dto.referenceLabel
                food.gramsPerReference = dto.gramsPerReference
                food.kcalPerReference = dto.kcalPerReference
                food.proteinPerReference = dto.proteinPerReference
                food.carbPerReference = dto.carbPerReference
                food.fatPerReference = dto.fatPerReference
                food.isArchived = dto.isArchived
                food.isFavorite = dto.isFavorite
                food.kindRaw = dto.kindRaw
                food.unitRaw = dto.unitRaw
                food.createdAt = dto.createdAt
                food.updatedAt = dto.updatedAt
            }

            for dto in payload.meals {
                let meal: Meal
                if let existing = mealsById[dto.id] {
                    meal = existing
                } else {
                    meal = Meal(
                        userId: userId,
                        name: dto.name,
                        defaultCategory: FoodLogCategory(rawValue: dto.defaultCategoryRaw) ?? .other
                    )
                    meal.id = dto.id
                    modelContext.insert(meal)
                    mealsById[dto.id] = meal
                }

                meal.userId = userId
                meal.name = dto.name
                meal.defaultCategoryRaw = dto.defaultCategoryRaw
                meal.createdAt = dto.createdAt
                meal.updatedAt = dto.updatedAt
            }

            for dto in payload.mealItems {
                guard let mealId = dto.mealId, let meal = mealsById[mealId] else {
                    throw BackupError.invalidBackup("Meal item \(dto.id) has missing meal reference.")
                }
                guard let food = foodsById[dto.foodId] else {
                    throw BackupError.invalidBackup("Meal item \(dto.id) has missing food reference.")
                }

                let item: MealItem
                if let existing = mealItemsById[dto.id] {
                    item = existing
                } else {
                    item = MealItem(order: dto.order, grams: dto.grams, meal: meal, food: food)
                    item.id = dto.id
                    modelContext.insert(item)
                    mealItemsById[dto.id] = item
                }

                item.order = dto.order
                item.grams = dto.grams
                item.meal = meal
                item.food = food
                if !meal.items.contains(where: { $0.id == item.id }) {
                    meal.items.append(item)
                }
            }

            for dto in payload.mealEntries {
                let templateMeal = dto.templateMealId.flatMap { mealsById[$0] }
                let entry: MealEntry
                if let existing = entriesById[dto.id] {
                    entry = existing
                } else {
                    entry = MealEntry(
                        userId: userId,
                        timestamp: dto.timestamp,
                        category: FoodLogCategory(rawValue: dto.categoryRaw) ?? .other,
                        note: dto.note,
                        templateMeal: templateMeal
                    )
                    entry.id = dto.id
                    modelContext.insert(entry)
                    entriesById[dto.id] = entry
                }

                entry.userId = userId
                entry.timestamp = dto.timestamp
                entry.categoryRaw = dto.categoryRaw
                entry.note = dto.note
                entry.templateMeal = templateMeal
            }

            for dto in payload.foodLogs {
                guard let food = foodsById[dto.foodId] else {
                    throw BackupError.invalidBackup("Food log \(dto.id) has missing food reference.")
                }
                let mealEntry = dto.mealEntryId.flatMap { entriesById[$0] }
                if dto.mealEntryId != nil, mealEntry == nil {
                    throw BackupError.invalidBackup("Food log \(dto.id) has missing meal entry reference.")
                }

                let log: FoodLog
                if let existing = logsById[dto.id] {
                    log = existing
                } else {
                    log = FoodLog(
                        userId: userId,
                        timestamp: dto.timestamp,
                        category: FoodLogCategory(rawValue: dto.categoryRaw) ?? .other,
                        grams: dto.grams,
                        note: dto.note,
                        quickCaloriesKcal: dto.quickCaloriesKcal,
                        food: food,
                        mealEntry: mealEntry
                    )
                    log.id = dto.id
                    modelContext.insert(log)
                    logsById[dto.id] = log
                }

                log.userId = userId
                log.timestamp = dto.timestamp
                log.categoryRaw = dto.categoryRaw
                log.grams = dto.grams
                log.note = dto.note
                log.quickCaloriesKcal = dto.quickCaloriesKcal
                log.food = food
                log.mealEntry = mealEntry
                if let mealEntry, !mealEntry.logs.contains(where: { $0.id == log.id }) {
                    mealEntry.logs.append(log)
                }
            }

            for dto in payload.nutritionTargets {
                let target: NutritionTarget
                if let existing = targetsById[dto.id] {
                    target = existing
                } else {
                    target = NutritionTarget(
                        calorieTarget: dto.calorieTarget,
                        proteinTarget: dto.proteinTarget,
                        carbTarget: dto.carbTarget,
                        fatTarget: dto.fatTarget,
                        isEnabled: dto.isEnabled
                    )
                    target.id = dto.id
                    modelContext.insert(target)
                    targetsById[dto.id] = target
                }

                target.createdAt = dto.createdAt
                target.updatedAt = dto.updatedAt
                target.calorieTarget = dto.calorieTarget
                target.proteinTarget = dto.proteinTarget
                target.carbTarget = dto.carbTarget
                target.fatTarget = dto.fatTarget
                target.isEnabled = dto.isEnabled
            }

            try modelContext.save()

            return ImportResult(
                foods: payload.foods.count,
                meals: payload.meals.count,
                mealItems: payload.mealItems.count,
                mealEntries: payload.mealEntries.count,
                foodLogs: payload.foodLogs.count,
                targets: payload.nutritionTargets.count
            )
        } catch let error as BackupError {
            throw error
        } catch {
            throw BackupError.persistence("Could not import nutrition backup.")
        }
    }

    private func fetchFoods(userId: UUID) throws -> [Food] {
        let descriptor = FetchDescriptor<Food>(
            predicate: #Predicate<Food> { item in
                item.userId == userId
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchMeals(userId: UUID) throws -> [Meal] {
        let descriptor = FetchDescriptor<Meal>(
            predicate: #Predicate<Meal> { item in
                item.userId == userId
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchMealEntries(userId: UUID) throws -> [MealEntry] {
        let descriptor = FetchDescriptor<MealEntry>(
            predicate: #Predicate<MealEntry> { item in
                item.userId == userId
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchFoodLogs(userId: UUID) throws -> [FoodLog] {
        let descriptor = FetchDescriptor<FoodLog>(
            predicate: #Predicate<FoodLog> { item in
                item.userId == userId
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchTargets() throws -> [NutritionTarget] {
        let descriptor = FetchDescriptor<NutritionTarget>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func mapFoodsById(_ foods: [Food]) -> [UUID: Food] {
        var map: [UUID: Food] = [:]
        for food in foods {
            if map[food.id] != nil {
                print("Duplicate food id detected for current user during import: \(food.id)")
                continue
            }
            map[food.id] = food
        }
        return map
    }

    private func mapMealsById(_ meals: [Meal]) -> [UUID: Meal] {
        var map: [UUID: Meal] = [:]
        for meal in meals {
            if map[meal.id] != nil {
                print("Duplicate meal id detected for current user during import: \(meal.id)")
                continue
            }
            map[meal.id] = meal
        }
        return map
    }

    private func mapMealEntriesById(_ entries: [MealEntry]) -> [UUID: MealEntry] {
        var map: [UUID: MealEntry] = [:]
        for entry in entries {
            if map[entry.id] != nil {
                print("Duplicate meal entry id detected for current user during import: \(entry.id)")
                continue
            }
            map[entry.id] = entry
        }
        return map
    }

    private func mapFoodLogsById(_ logs: [FoodLog]) -> [UUID: FoodLog] {
        var map: [UUID: FoodLog] = [:]
        for log in logs {
            if map[log.id] != nil {
                print("Duplicate food log id detected for current user during import: \(log.id)")
                continue
            }
            map[log.id] = log
        }
        return map
    }

    private func mapTargetsById(_ targets: [NutritionTarget]) -> [UUID: NutritionTarget] {
        var map: [UUID: NutritionTarget] = [:]
        for target in targets {
            if map[target.id] != nil {
                print("Duplicate nutrition target id detected during import: \(target.id)")
                continue
            }
            map[target.id] = target
        }
        return map
    }

    private func backupURL() -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let fileName = "nutrition-backup-\(stamp).json"

        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return documents.appendingPathComponent(fileName)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }
}

private struct NutritionBackupPayload: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let userId: UUID
    let foods: [FoodBackupDTO]
    let meals: [MealBackupDTO]
    let mealItems: [MealItemBackupDTO]
    let mealEntries: [MealEntryBackupDTO]
    let foodLogs: [FoodLogBackupDTO]
    let nutritionTargets: [NutritionTargetBackupDTO]
}

private struct FoodBackupDTO: Codable {
    let id: UUID
    let userId: UUID
    let name: String
    let brand: String?
    let referenceLabel: String?
    let gramsPerReference: Double
    let kcalPerReference: Double
    let proteinPerReference: Double
    let carbPerReference: Double
    let fatPerReference: Double
    let isArchived: Bool
    let isFavorite: Bool
    let kindRaw: Int
    let unitRaw: Int
    let createdAt: Date
    let updatedAt: Date

    init(_ food: Food) {
        id = food.id
        userId = food.userId
        name = food.name
        brand = food.brand
        referenceLabel = food.referenceLabel
        gramsPerReference = food.gramsPerReference
        kcalPerReference = food.kcalPerReference
        proteinPerReference = food.proteinPerReference
        carbPerReference = food.carbPerReference
        fatPerReference = food.fatPerReference
        isArchived = food.isArchived
        isFavorite = food.isFavorite
        kindRaw = food.kindRaw
        unitRaw = food.unitRaw
        createdAt = food.createdAt
        updatedAt = food.updatedAt
    }
}

private struct MealBackupDTO: Codable {
    let id: UUID
    let userId: UUID
    let name: String
    let defaultCategoryRaw: Int
    let createdAt: Date
    let updatedAt: Date

    init(_ meal: Meal) {
        id = meal.id
        userId = meal.userId
        name = meal.name
        defaultCategoryRaw = meal.defaultCategoryRaw
        createdAt = meal.createdAt
        updatedAt = meal.updatedAt
    }
}

private struct MealItemBackupDTO: Codable {
    let id: UUID
    let mealId: UUID?
    let foodId: UUID
    let order: Int
    let grams: Double

    init(_ item: MealItem) {
        id = item.id
        mealId = item.meal?.id
        foodId = item.food.id
        order = item.order
        grams = item.grams
    }
}

private struct MealEntryBackupDTO: Codable {
    let id: UUID
    let userId: UUID
    let timestamp: Date
    let categoryRaw: Int
    let note: String?
    let templateMealId: UUID?

    init(_ entry: MealEntry) {
        id = entry.id
        userId = entry.userId
        timestamp = entry.timestamp
        categoryRaw = entry.categoryRaw
        note = entry.note
        templateMealId = entry.templateMeal?.id
    }
}

private struct FoodLogBackupDTO: Codable {
    let id: UUID
    let userId: UUID
    let timestamp: Date
    let categoryRaw: Int
    let grams: Double
    let note: String?
    let quickCaloriesKcal: Double?
    let foodId: UUID
    let mealEntryId: UUID?

    init(_ log: FoodLog) {
        id = log.id
        userId = log.userId
        timestamp = log.timestamp
        categoryRaw = log.categoryRaw
        grams = log.grams
        note = log.note
        quickCaloriesKcal = log.quickCaloriesKcal
        foodId = log.food.id
        mealEntryId = log.mealEntry?.id
    }
}

private struct NutritionTargetBackupDTO: Codable {
    let id: UUID
    let createdAt: Date
    let updatedAt: Date
    let calorieTarget: Double
    let proteinTarget: Double
    let carbTarget: Double
    let fatTarget: Double
    let isEnabled: Bool

    init(_ target: NutritionTarget) {
        id = target.id
        createdAt = target.createdAt
        updatedAt = target.updatedAt
        calorieTarget = target.calorieTarget
        proteinTarget = target.proteinTarget
        carbTarget = target.carbTarget
        fatTarget = target.fatTarget
        isEnabled = target.isEnabled
    }
}
