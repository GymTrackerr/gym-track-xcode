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
        let foodItems: Int
        let mealRecipes: Int
        let mealRecipeItems: Int
        let nutritionLogEntries: Int
    }

    private let modelContext: ModelContext
    private let currentUserProvider: () -> User?

    init(context: ModelContext, currentUserProvider: @escaping () -> User?) {
        self.modelContext = context
        self.currentUserProvider = currentUserProvider
    }

    // MARK: - Export

    func exportNutritionJSON() throws -> URL {
        guard let userId = currentUserProvider()?.id else {
            throw BackupError.missingUser
        }

        if try shouldExportV2(userId: userId) {
            return try exportV2NutritionJSON(userId: userId)
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
        try validateV1Payload(payload)

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

    // MARK: - Import

    func importNutritionJSON(from url: URL) throws -> ImportResult {
        guard let userId = currentUserProvider()?.id else {
            throw BackupError.missingUser
        }

        let data = try readBackupData(from: url)
        let schemaVersion = try decodeSchemaVersion(from: data)

        do {
            switch schemaVersion {
            case 1:
                let payload = try decodeBackupPayload(from: data)
                try validateV1Payload(payload)
                let result = try importV1AsV2(payload: payload, userId: userId)
                try modelContext.save()
                return result
            case 2:
                let payload = try decodeV2BackupPayload(from: data)
                let result = try importV2(payload: payload, userId: userId)
                try modelContext.save()
                return result
            default:
                throw BackupError.invalidSchemaVersion(schemaVersion)
            }
        } catch let error as BackupError {
            modelContext.rollback()
            throw error
        } catch {
            modelContext.rollback()
            throw BackupError.persistence("Could not import nutrition backup.")
        }
    }

    // MARK: - Data Loading

    private func readBackupData(from url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw BackupError.persistence("Could not read backup file.")
        }
    }

    private func decodeBackupPayload(from data: Data) throws -> NutritionBackupPayload {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(NutritionBackupPayload.self, from: data)
        } catch {
            throw BackupError.invalidBackup("Backup file format is invalid.")
        }
    }

    private func validateV1Payload(_ payload: NutritionBackupPayload) throws {
        var foodIDs = Set<UUID>()
        for food in payload.foods {
            guard foodIDs.insert(food.id).inserted else {
                throw BackupError.invalidBackup("Duplicate food id found in backup: \(food.id)")
            }
        }

        var mealIDs = Set<UUID>()
        for meal in payload.meals {
            guard mealIDs.insert(meal.id).inserted else {
                throw BackupError.invalidBackup("Duplicate meal id found in backup: \(meal.id)")
            }
        }

        var mealEntryIDs = Set<UUID>()
        for entry in payload.mealEntries {
            guard mealEntryIDs.insert(entry.id).inserted else {
                throw BackupError.invalidBackup("Duplicate meal entry id found in backup: \(entry.id)")
            }
            if let templateMealId = entry.templateMealId, !mealIDs.contains(templateMealId) {
                throw BackupError.invalidBackup("Meal entry \(entry.id) references missing template meal \(templateMealId).")
            }
        }

        var mealItemIDs = Set<UUID>()
        for item in payload.mealItems {
            guard mealItemIDs.insert(item.id).inserted else {
                throw BackupError.invalidBackup("Duplicate meal item id found in backup: \(item.id)")
            }
            guard let mealId = item.mealId else {
                throw BackupError.invalidBackup("Meal item \(item.id) is missing mealId.")
            }
            guard mealIDs.contains(mealId) else {
                throw BackupError.invalidBackup("Meal item \(item.id) references missing meal \(mealId).")
            }
            guard foodIDs.contains(item.foodId) else {
                throw BackupError.invalidBackup("Meal item \(item.id) references missing food \(item.foodId).")
            }
        }

        var foodLogIDs = Set<UUID>()
        for log in payload.foodLogs {
            guard foodLogIDs.insert(log.id).inserted else {
                throw BackupError.invalidBackup("Duplicate food log id found in backup: \(log.id)")
            }
            guard foodIDs.contains(log.foodId) else {
                throw BackupError.invalidBackup("Food log \(log.id) references missing food \(log.foodId).")
            }
            if let mealEntryId = log.mealEntryId, !mealEntryIDs.contains(mealEntryId) {
                throw BackupError.invalidBackup("Food log \(log.id) references missing meal entry \(mealEntryId).")
            }
        }

        var targetIDs = Set<UUID>()
        for target in payload.nutritionTargets {
            guard targetIDs.insert(target.id).inserted else {
                throw BackupError.invalidBackup("Duplicate nutrition target id found in backup: \(target.id)")
            }
        }
    }

    private func decodeSchemaVersion(from data: Data) throws -> Int {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let version = json["schemaVersion"] as? Int
        else {
            throw BackupError.invalidBackup("Backup file format is invalid.")
        }
        return version
    }

    private func decodeV2BackupPayload(from data: Data) throws -> NutritionBackupPayloadV2 {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(NutritionBackupPayloadV2.self, from: data)
        } catch {
            throw BackupError.invalidBackup("Backup file format is invalid.")
        }
    }

    private func shouldExportV2(userId: UUID) throws -> Bool {
        let hasFoodItems = !(try fetchFoodItems(userId: userId).isEmpty)
        let hasMealRecipes = !(try fetchMealRecipes(userId: userId).isEmpty)
        let hasNutritionLogs = !(try fetchNutritionLogEntries(userId: userId).isEmpty)
        return hasFoodItems || hasMealRecipes || hasNutritionLogs
    }

    private func exportV2NutritionJSON(userId: UUID) throws -> URL {
        let foodItems = try fetchFoodItems(userId: userId)
        let mealRecipes = try fetchMealRecipes(userId: userId)
        let mealRecipeItems = mealRecipes
            .flatMap { $0.items }
            .sorted { lhs, rhs in
                if lhs.mealRecipe?.id == rhs.mealRecipe?.id {
                    return lhs.order < rhs.order
                }
                return (lhs.mealRecipe?.id.uuidString ?? "") < (rhs.mealRecipe?.id.uuidString ?? "")
            }
        let nutritionLogs = try fetchNutritionLogEntries(userId: userId)
        let targets = try fetchTargets()

        let payload = NutritionBackupPayloadV2(
            schemaVersion: 2,
            exportedAt: Date(),
            userId: userId,
            foodItems: foodItems.map(FoodItemBackupDTO.init),
            mealRecipes: mealRecipes.map(MealRecipeBackupDTO.init),
            mealRecipeItems: mealRecipeItems.map(MealRecipeItemBackupDTO.init),
            nutritionLogEntries: nutritionLogs.map(NutritionLogEntryBackupDTO.init),
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

    private func importV1AsV2(payload: NutritionBackupPayload, userId: UUID) throws -> ImportResult {
        let existingFoodItems = Dictionary(uniqueKeysWithValues: try fetchFoodItems(userId: userId).map { ($0.id, $0) })
        let existingMealRecipes = Dictionary(uniqueKeysWithValues: try fetchMealRecipes(userId: userId).map { ($0.id, $0) })
        let existingMealRecipeItems = Dictionary(uniqueKeysWithValues: try fetchMealRecipeItems(userId: userId).map { ($0.id, $0) })
        let existingLogs = Dictionary(uniqueKeysWithValues: try fetchNutritionLogEntries(userId: userId).map { ($0.id, $0) })
        let existingTargets = Dictionary(uniqueKeysWithValues: try fetchTargets().map { ($0.id, $0) })

        var foodItemsById: [UUID: FoodItem] = existingFoodItems
        for dto in payload.foods {
            let item = foodItemsById[dto.id] ?? FoodItem(
                userId: userId,
                name: dto.name,
                brand: dto.brand,
                referenceLabel: dto.referenceLabel,
                referenceQuantity: dto.gramsPerReference,
                caloriesPerReference: dto.kcalPerReference,
                proteinPerReference: dto.proteinPerReference,
                carbsPerReference: dto.carbPerReference,
                fatPerReference: dto.fatPerReference,
                extraNutrients: nil,
                isArchived: dto.isArchived,
                isFavorite: dto.isFavorite,
                kind: migrateFoodKind(dto.kindRaw),
                unit: migrateFoodUnit(dto.unitRaw)
            )
            if foodItemsById[dto.id] == nil {
                item.id = dto.id
                modelContext.insert(item)
            }
            item.userId = userId
            item.name = dto.name
            item.brand = dto.brand
            item.referenceLabel = dto.referenceLabel
            item.referenceQuantity = max(0.0001, dto.gramsPerReference)
            item.caloriesPerReference = max(0, dto.kcalPerReference)
            item.proteinPerReference = max(0, dto.proteinPerReference)
            item.carbsPerReference = max(0, dto.carbPerReference)
            item.fatPerReference = max(0, dto.fatPerReference)
            item.extraNutrients = nil
            item.isArchived = dto.isArchived
            item.isFavorite = dto.isFavorite
            item.kind = migrateFoodKind(dto.kindRaw)
            item.unit = migrateFoodUnit(dto.unitRaw)
            item.createdAt = dto.createdAt
            item.updatedAt = dto.updatedAt
            foodItemsById[dto.id] = item
        }

        var mealRecipesById: [UUID: MealRecipe] = existingMealRecipes
        for dto in payload.meals {
            let recipe = mealRecipesById[dto.id] ?? MealRecipe(
                userId: userId,
                name: dto.name,
                batchSize: 1,
                servingUnitLabel: "serving",
                defaultCategory: FoodLogCategory(rawValue: dto.defaultCategoryRaw) ?? .other,
                cachedExtraNutrients: nil,
                isArchived: false
            )
            if mealRecipesById[dto.id] == nil {
                recipe.id = dto.id
                modelContext.insert(recipe)
            }
            recipe.userId = userId
            recipe.name = dto.name
            recipe.batchSize = 1
            recipe.servingUnitLabel = "serving"
            recipe.defaultCategory = FoodLogCategory(rawValue: dto.defaultCategoryRaw) ?? .other
            recipe.cachedExtraNutrients = nil
            recipe.isArchived = false
            recipe.createdAt = dto.createdAt
            recipe.updatedAt = dto.updatedAt
            mealRecipesById[dto.id] = recipe
        }

        for dto in payload.mealItems {
            guard let mealId = dto.mealId, let mealRecipe = mealRecipesById[mealId] else {
                throw BackupError.invalidBackup("Meal item \(dto.id) has missing meal reference.")
            }
            guard let foodItem = foodItemsById[dto.foodId] else {
                throw BackupError.invalidBackup("Meal item \(dto.id) has missing food reference.")
            }
            let recipeItem = existingMealRecipeItems[dto.id] ?? MealRecipeItem(
                amount: dto.grams,
                amountUnit: .grams,
                order: dto.order,
                mealRecipe: mealRecipe,
                foodItem: foodItem
            )
            if existingMealRecipeItems[dto.id] == nil {
                recipeItem.id = dto.id
                modelContext.insert(recipeItem)
            }
            recipeItem.amount = max(0, dto.grams)
            recipeItem.amountUnit = .grams
            recipeItem.order = dto.order
            recipeItem.mealRecipe = mealRecipe
            recipeItem.foodItem = foodItem
        }

        let foodBackupsById = Dictionary(uniqueKeysWithValues: payload.foods.map { ($0.id, $0) })
        let logsByMealEntry = Dictionary(grouping: payload.foodLogs.filter { $0.mealEntryId != nil }) { $0.mealEntryId! }

        for dto in payload.foodLogs where dto.mealEntryId == nil {
            let draft = try buildImportedDraftFromV1Standalone(dto: dto, foodBackupsById: foodBackupsById, userId: userId)
            let id = dto.id
            if let existing = existingLogs[id] {
                updateLog(existing, from: draft, userId: userId)
            } else {
                let log = createNutritionLogEntry(from: draft, userId: userId)
                log.id = id
                modelContext.insert(log)
            }
        }

        for mealEntry in payload.mealEntries {
            let childLogs = logsByMealEntry[mealEntry.id] ?? []
            let mealRecipe = mealEntry.templateMealId.flatMap { mealRecipesById[$0] }
            let draft = buildImportedDraftFromV1MealEntry(
                mealEntry: mealEntry,
                childLogs: childLogs,
                foodBackupsById: foodBackupsById,
                mealRecipe: mealRecipe
            )
            let id = mealEntry.id
            if let existing = existingLogs[id] {
                updateLog(existing, from: draft, userId: userId)
            } else {
                let log = createNutritionLogEntry(from: draft, userId: userId)
                log.id = id
                modelContext.insert(log)
            }
        }

        for dto in payload.nutritionTargets {
            let target = existingTargets[dto.id] ?? NutritionTarget(
                calorieTarget: dto.calorieTarget,
                proteinTarget: dto.proteinTarget,
                carbTarget: dto.carbTarget,
                fatTarget: dto.fatTarget,
                isEnabled: dto.isEnabled
            )
            if existingTargets[dto.id] == nil {
                target.id = dto.id
                modelContext.insert(target)
            }
            target.createdAt = dto.createdAt
            target.updatedAt = dto.updatedAt
            target.calorieTarget = dto.calorieTarget
            target.proteinTarget = dto.proteinTarget
            target.carbTarget = dto.carbTarget
            target.fatTarget = dto.fatTarget
            target.isEnabled = dto.isEnabled
        }

        return ImportResult(
            foods: payload.foods.count,
            meals: payload.meals.count,
            mealItems: payload.mealItems.count,
            mealEntries: payload.mealEntries.count,
            foodLogs: payload.foodLogs.count,
            targets: payload.nutritionTargets.count,
            foodItems: payload.foods.count,
            mealRecipes: payload.meals.count,
            mealRecipeItems: payload.mealItems.count,
            nutritionLogEntries: payload.foodLogs.filter { $0.mealEntryId == nil }.count + payload.mealEntries.count
        )
    }

    private func importV2(payload: NutritionBackupPayloadV2, userId: UUID) throws -> ImportResult {
        let existingFoodItems = Dictionary(uniqueKeysWithValues: try fetchFoodItems(userId: userId).map { ($0.id, $0) })
        let existingMealRecipes = Dictionary(uniqueKeysWithValues: try fetchMealRecipes(userId: userId).map { ($0.id, $0) })
        let existingMealRecipeItems = Dictionary(uniqueKeysWithValues: try fetchMealRecipeItems(userId: userId).map { ($0.id, $0) })
        let existingLogs = Dictionary(uniqueKeysWithValues: try fetchNutritionLogEntries(userId: userId).map { ($0.id, $0) })
        let existingTargets = Dictionary(uniqueKeysWithValues: try fetchTargets().map { ($0.id, $0) })

        var foodItemsById: [UUID: FoodItem] = existingFoodItems
        for dto in payload.foodItems {
            let item = foodItemsById[dto.id] ?? FoodItem(
                userId: userId,
                name: dto.name,
                brand: dto.brand,
                referenceLabel: dto.referenceLabel,
                referenceQuantity: dto.referenceQuantity,
                caloriesPerReference: dto.caloriesPerReference,
                proteinPerReference: dto.proteinPerReference,
                carbsPerReference: dto.carbsPerReference,
                fatPerReference: dto.fatPerReference,
                extraNutrients: dto.extraNutrients,
                isArchived: dto.isArchived,
                isFavorite: dto.isFavorite,
                kind: FoodItemKind(rawValue: dto.kindRaw) ?? .food,
                unit: FoodItemUnit(rawValue: dto.unitRaw) ?? .grams
            )
            if foodItemsById[dto.id] == nil {
                item.id = dto.id
                modelContext.insert(item)
            }
            item.userId = userId
            item.name = dto.name
            item.brand = dto.brand
            item.referenceLabel = dto.referenceLabel
            item.referenceQuantity = max(0.0001, dto.referenceQuantity)
            item.caloriesPerReference = max(0, dto.caloriesPerReference)
            item.proteinPerReference = max(0, dto.proteinPerReference)
            item.carbsPerReference = max(0, dto.carbsPerReference)
            item.fatPerReference = max(0, dto.fatPerReference)
            item.extraNutrients = dto.extraNutrients
            item.isArchived = dto.isArchived
            item.isFavorite = dto.isFavorite
            item.kind = FoodItemKind(rawValue: dto.kindRaw) ?? .food
            item.unit = FoodItemUnit(rawValue: dto.unitRaw) ?? .grams
            item.createdAt = dto.createdAt
            item.updatedAt = dto.updatedAt
            foodItemsById[dto.id] = item
        }

        var mealRecipesById: [UUID: MealRecipe] = existingMealRecipes
        for dto in payload.mealRecipes {
            let recipe = mealRecipesById[dto.id] ?? MealRecipe(
                userId: userId,
                name: dto.name,
                batchSize: dto.batchSize,
                servingUnitLabel: dto.servingUnitLabel,
                defaultCategory: FoodLogCategory(rawValue: dto.defaultCategoryRaw) ?? .other,
                cachedExtraNutrients: dto.cachedExtraNutrients,
                isArchived: dto.isArchived
            )
            if mealRecipesById[dto.id] == nil {
                recipe.id = dto.id
                modelContext.insert(recipe)
            }
            recipe.userId = userId
            recipe.name = dto.name
            recipe.batchSize = max(0.0001, dto.batchSize)
            recipe.servingUnitLabel = dto.servingUnitLabel
            recipe.defaultCategory = FoodLogCategory(rawValue: dto.defaultCategoryRaw) ?? .other
            recipe.cachedExtraNutrients = dto.cachedExtraNutrients
            recipe.isArchived = dto.isArchived
            recipe.createdAt = dto.createdAt
            recipe.updatedAt = dto.updatedAt
            mealRecipesById[dto.id] = recipe
        }

        for dto in payload.mealRecipeItems {
            guard let mealRecipeId = dto.mealRecipeId, let mealRecipe = mealRecipesById[mealRecipeId] else {
                throw BackupError.invalidBackup("Meal recipe item \(dto.id) has missing meal recipe reference.")
            }
            guard let foodItem = foodItemsById[dto.foodItemId] else {
                throw BackupError.invalidBackup("Meal recipe item \(dto.id) has missing food item reference.")
            }
            let recipeItem = existingMealRecipeItems[dto.id] ?? MealRecipeItem(
                amount: dto.amount,
                amountUnit: FoodItemUnit(rawValue: dto.amountUnitRaw) ?? .grams,
                order: dto.order,
                mealRecipe: mealRecipe,
                foodItem: foodItem
            )
            if existingMealRecipeItems[dto.id] == nil {
                recipeItem.id = dto.id
                modelContext.insert(recipeItem)
            }
            recipeItem.amount = max(0, dto.amount)
            recipeItem.amountUnit = FoodItemUnit(rawValue: dto.amountUnitRaw) ?? .grams
            recipeItem.order = dto.order
            recipeItem.mealRecipe = mealRecipe
            recipeItem.foodItem = foodItem
        }

        for dto in payload.nutritionLogEntries {
            let draft = NutritionLogDraft(
                logType: NutritionLogType(rawValue: dto.logTypeRaw) ?? .food,
                creationMethod: LogCreationMethod(rawValue: dto.creationMethodRaw) ?? .importedBackup,
                sourceItemId: dto.sourceItemId,
                sourceMealId: dto.sourceMealId,
                nameSnapshot: dto.nameSnapshot,
                brandSnapshot: dto.brandSnapshot,
                amount: dto.amount,
                amountUnitSnapshot: dto.amountUnitSnapshot,
                servingUnitLabelSnapshot: dto.servingUnitLabelSnapshot,
                caloriesSnapshot: dto.caloriesSnapshot,
                proteinSnapshot: dto.proteinSnapshot,
                carbsSnapshot: dto.carbsSnapshot,
                fatSnapshot: dto.fatSnapshot,
                extraNutrientsSnapshot: dto.extraNutrientsSnapshot,
                recipeItemsSnapshot: dto.recipeItemsSnapshot,
                timestamp: dto.timestamp,
                category: FoodLogCategory(rawValue: dto.categoryRaw) ?? .other,
                note: dto.note
            )
            try validateDraft(draft)
            if let existing = existingLogs[dto.id] {
                updateLog(existing, from: draft, userId: userId)
                existing.dayKey = dto.dayKey
                existing.logDate = dto.logDate
                existing.createdAt = dto.createdAt
                existing.updatedAt = dto.updatedAt
            } else {
                let log = createNutritionLogEntry(from: draft, userId: userId)
                log.id = dto.id
                log.dayKey = dto.dayKey
                log.logDate = dto.logDate
                log.createdAt = dto.createdAt
                log.updatedAt = dto.updatedAt
                modelContext.insert(log)
            }
        }

        for dto in payload.nutritionTargets {
            let target = existingTargets[dto.id] ?? NutritionTarget(
                calorieTarget: dto.calorieTarget,
                proteinTarget: dto.proteinTarget,
                carbTarget: dto.carbTarget,
                fatTarget: dto.fatTarget,
                isEnabled: dto.isEnabled
            )
            if existingTargets[dto.id] == nil {
                target.id = dto.id
                modelContext.insert(target)
            }
            target.createdAt = dto.createdAt
            target.updatedAt = dto.updatedAt
            target.calorieTarget = dto.calorieTarget
            target.proteinTarget = dto.proteinTarget
            target.carbTarget = dto.carbTarget
            target.fatTarget = dto.fatTarget
            target.isEnabled = dto.isEnabled
        }

        return ImportResult(
            foods: 0,
            meals: 0,
            mealItems: 0,
            mealEntries: 0,
            foodLogs: 0,
            targets: payload.nutritionTargets.count,
            foodItems: payload.foodItems.count,
            mealRecipes: payload.mealRecipes.count,
            mealRecipeItems: payload.mealRecipeItems.count,
            nutritionLogEntries: payload.nutritionLogEntries.count
        )
    }

    private func buildImportedDraftFromV1Standalone(
        dto: FoodLogBackupDTO,
        foodBackupsById: [UUID: FoodBackupDTO],
        userId: UUID
    ) throws -> NutritionLogDraft {
        let category = FoodLogCategory(rawValue: dto.categoryRaw) ?? .other
        if let quick = dto.quickCaloriesKcal {
            return NutritionLogDraft(
                logType: .quickCalories,
                creationMethod: .migratedV1,
                sourceItemId: nil,
                sourceMealId: nil,
                nameSnapshot: "Quick Entry",
                brandSnapshot: nil,
                amount: max(0, quick),
                amountUnitSnapshot: "kcal",
                servingUnitLabelSnapshot: nil,
                caloriesSnapshot: max(0, quick),
                proteinSnapshot: 0,
                carbsSnapshot: 0,
                fatSnapshot: 0,
                extraNutrientsSnapshot: nil,
                recipeItemsSnapshot: nil,
                timestamp: dto.timestamp,
                category: category,
                note: dto.note
            )
        }

        guard let foodBackup = foodBackupsById[dto.foodId] else {
            throw BackupError.invalidBackup("Food log \(dto.id) references missing food \(dto.foodId).")
        }
        let grams = max(0, dto.grams)
        let reference = max(foodBackup.gramsPerReference, 0.0001)
        let factor = grams / reference
        let unit = migrateFoodUnit(foodBackup.unitRaw)

        return NutritionLogDraft(
            logType: .food,
            creationMethod: .migratedV1,
            sourceItemId: foodBackup.id,
            sourceMealId: nil,
            nameSnapshot: foodBackup.name,
            brandSnapshot: foodBackup.brand,
            amount: grams,
            amountUnitSnapshot: unit.shortLabel,
            servingUnitLabelSnapshot: nil,
            caloriesSnapshot: max(0, foodBackup.kcalPerReference * factor),
            proteinSnapshot: max(0, foodBackup.proteinPerReference * factor),
            carbsSnapshot: max(0, foodBackup.carbPerReference * factor),
            fatSnapshot: max(0, foodBackup.fatPerReference * factor),
            extraNutrientsSnapshot: nil,
            recipeItemsSnapshot: nil,
            timestamp: dto.timestamp,
            category: category,
            note: dto.note
        )
    }

    private func buildImportedDraftFromV1MealEntry(
        mealEntry: MealEntryBackupDTO,
        childLogs: [FoodLogBackupDTO],
        foodBackupsById: [UUID: FoodBackupDTO],
        mealRecipe: MealRecipe?
    ) -> NutritionLogDraft {
        let category = FoodLogCategory(rawValue: mealEntry.categoryRaw) ?? .other
        let calories = childLogs.reduce(0) { partial, child in
            if let quick = child.quickCaloriesKcal { return partial + quick }
            guard let food = foodBackupsById[child.foodId] else { return partial }
            let reference = max(food.gramsPerReference, 0.0001)
            return partial + (max(0, child.grams) / reference) * food.kcalPerReference
        }
        let protein = childLogs.reduce(0) { partial, child in
            guard child.quickCaloriesKcal == nil, let food = foodBackupsById[child.foodId] else { return partial }
            let reference = max(food.gramsPerReference, 0.0001)
            return partial + (max(0, child.grams) / reference) * food.proteinPerReference
        }
        let carbs = childLogs.reduce(0) { partial, child in
            guard child.quickCaloriesKcal == nil, let food = foodBackupsById[child.foodId] else { return partial }
            let reference = max(food.gramsPerReference, 0.0001)
            return partial + (max(0, child.grams) / reference) * food.carbPerReference
        }
        let fat = childLogs.reduce(0) { partial, child in
            guard child.quickCaloriesKcal == nil, let food = foodBackupsById[child.foodId] else { return partial }
            let reference = max(food.gramsPerReference, 0.0001)
            return partial + (max(0, child.grams) / reference) * food.fatPerReference
        }

        let snapshots: [RecipeItemSnapshot] = childLogs.compactMap { child in
            guard let food = foodBackupsById[child.foodId] else { return nil }
            let reference = max(food.gramsPerReference, 0.0001)
            let factor = max(0, child.grams) / reference
            return RecipeItemSnapshot(
                name: food.name,
                amount: max(0, child.grams),
                amountUnit: migrateFoodUnit(food.unitRaw).shortLabel,
                caloriesSnapshot: max(0, food.kcalPerReference * factor),
                proteinSnapshot: max(0, food.proteinPerReference * factor),
                carbsSnapshot: max(0, food.carbPerReference * factor),
                fatSnapshot: max(0, food.fatPerReference * factor),
                extraNutrientsSnapshot: nil
            )
        }

        return NutritionLogDraft(
            logType: .meal,
            creationMethod: .migratedV1,
            sourceItemId: nil,
            sourceMealId: mealEntry.templateMealId,
            nameSnapshot: mealRecipe?.name ?? "Meal",
            brandSnapshot: nil,
            amount: 1,
            amountUnitSnapshot: mealRecipe?.servingUnitLabel ?? "serving",
            servingUnitLabelSnapshot: mealRecipe?.servingUnitLabel ?? "serving",
            caloriesSnapshot: max(0, calories),
            proteinSnapshot: max(0, protein),
            carbsSnapshot: max(0, carbs),
            fatSnapshot: max(0, fat),
            extraNutrientsSnapshot: nil,
            recipeItemsSnapshot: snapshots.isEmpty ? nil : snapshots,
            timestamp: mealEntry.timestamp,
            category: category,
            note: normalizedOptionalText(mealEntry.note)
                ?? childLogs.compactMap { normalizedOptionalText($0.note) }.first
        )
    }

    private func validateDraft(_ draft: NutritionLogDraft) throws {
        if draft.nameSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw BackupError.invalidBackup("Nutrition log entry is missing name snapshot.")
        }
        if draft.amountUnitSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw BackupError.invalidBackup("Nutrition log entry is missing amount unit snapshot.")
        }
        if draft.caloriesSnapshot < 0 || draft.proteinSnapshot < 0 || draft.carbsSnapshot < 0 || draft.fatSnapshot < 0 {
            throw BackupError.invalidBackup("Nutrition log entry has invalid negative macro snapshots.")
        }
        if draft.logType != .meal, draft.recipeItemsSnapshot != nil {
            throw BackupError.invalidBackup("Only meal logs can include recipe item snapshots.")
        }
    }

    private func createNutritionLogEntry(from draft: NutritionLogDraft, userId: UUID) -> NutritionLogEntry {
        let dayKey = computeDayKey(timestamp: draft.timestamp)
        let logDate = computeLogDate(timestamp: draft.timestamp)
        return NutritionLogEntry(
            userId: userId,
            timestamp: draft.timestamp,
            logType: draft.logType,
            sourceItemId: draft.sourceItemId,
            sourceMealId: draft.sourceMealId,
            amount: draft.amount,
            amountUnitSnapshot: draft.amountUnitSnapshot,
            category: draft.category,
            note: normalizedOptionalText(draft.note),
            dayKey: dayKey,
            logDate: logDate,
            creationMethod: draft.creationMethod,
            nameSnapshot: draft.nameSnapshot,
            brandSnapshot: normalizedOptionalText(draft.brandSnapshot),
            servingUnitLabelSnapshot: normalizedOptionalText(draft.servingUnitLabelSnapshot),
            caloriesSnapshot: max(0, draft.caloriesSnapshot),
            proteinSnapshot: max(0, draft.proteinSnapshot),
            carbsSnapshot: max(0, draft.carbsSnapshot),
            fatSnapshot: max(0, draft.fatSnapshot),
            extraNutrientsSnapshot: draft.extraNutrientsSnapshot,
            recipeItemsSnapshot: draft.recipeItemsSnapshot
        )
    }

    private func updateLog(_ log: NutritionLogEntry, from draft: NutritionLogDraft, userId: UUID) {
        log.userId = userId
        log.timestamp = draft.timestamp
        log.logType = draft.logType
        log.sourceItemId = draft.sourceItemId
        log.sourceMealId = draft.sourceMealId
        log.amount = max(0, draft.amount)
        log.amountUnitSnapshot = draft.amountUnitSnapshot
        log.category = draft.category
        log.note = normalizedOptionalText(draft.note)
        log.dayKey = computeDayKey(timestamp: draft.timestamp)
        log.logDate = computeLogDate(timestamp: draft.timestamp)
        log.creationMethod = draft.creationMethod
        log.nameSnapshot = draft.nameSnapshot
        log.brandSnapshot = normalizedOptionalText(draft.brandSnapshot)
        log.servingUnitLabelSnapshot = normalizedOptionalText(draft.servingUnitLabelSnapshot)
        log.caloriesSnapshot = max(0, draft.caloriesSnapshot)
        log.proteinSnapshot = max(0, draft.proteinSnapshot)
        log.carbsSnapshot = max(0, draft.carbsSnapshot)
        log.fatSnapshot = max(0, draft.fatSnapshot)
        log.extraNutrientsSnapshot = draft.extraNutrientsSnapshot
        log.recipeItemsSnapshot = draft.recipeItemsSnapshot
        log.updatedAt = Date()
    }

    private func computeDayKey(timestamp: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: timestamp)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private func computeLogDate(timestamp: Date, timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.startOfDay(for: timestamp)
    }

    private func normalizedOptionalText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func migrateFoodKind(_ rawValue: Int) -> FoodItemKind {
        switch rawValue {
        case FoodKind.drink.rawValue:
            return .drink
        default:
            return .food
        }
    }

    private func migrateFoodUnit(_ rawValue: Int) -> FoodItemUnit {
        switch rawValue {
        case FoodUnit.milliliters.rawValue:
            return .milliliters
        default:
            return .grams
        }
    }

    private func buildImportMaps(userId: UUID) throws -> NutritionImportMaps {
        NutritionImportMaps(
            foodsById: mapFoodsById(try fetchFoods(userId: userId)),
            mealsById: mapMealsById(try fetchMeals(userId: userId)),
            entriesById: mapMealEntriesById(try fetchMealEntries(userId: userId)),
            logsById: mapFoodLogsById(try fetchFoodLogs(userId: userId)),
            mealItemsById: try mapMealItemsById(userId: userId),
            targetsById: mapTargetsById(try fetchTargets())
        )
    }

    private func mapMealItemsById(userId: UUID) throws -> [UUID: MealItem] {
        let allMealItems = try modelContext.fetch(FetchDescriptor<MealItem>())
        var mealItemsById: [UUID: MealItem] = [:]
        for item in allMealItems where item.meal?.userId == userId {
            if mealItemsById[item.id] != nil {
                print("Duplicate meal item id detected for current user during import: \(item.id)")
                continue
            }
            mealItemsById[item.id] = item
        }
        return mealItemsById
    }

    // MARK: - Queries

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

    private func fetchFoodItems(userId: UUID) throws -> [FoodItem] {
        let descriptor = FetchDescriptor<FoodItem>(
            predicate: #Predicate<FoodItem> { item in
                item.userId == userId
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchMealRecipes(userId: UUID) throws -> [MealRecipe] {
        let descriptor = FetchDescriptor<MealRecipe>(
            predicate: #Predicate<MealRecipe> { item in
                item.userId == userId
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchMealRecipeItems(userId: UUID) throws -> [MealRecipeItem] {
        let allItems = try modelContext.fetch(FetchDescriptor<MealRecipeItem>())
        return allItems.filter { $0.mealRecipe?.userId == userId }
    }

    private func fetchNutritionLogEntries(userId: UUID) throws -> [NutritionLogEntry] {
        let descriptor = FetchDescriptor<NutritionLogEntry>(
            predicate: #Predicate<NutritionLogEntry> { item in
                item.userId == userId
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Map Builders

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

    // MARK: - File Output

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

private struct NutritionImportMaps {
    var foodsById: [UUID: Food]
    var mealsById: [UUID: Meal]
    var entriesById: [UUID: MealEntry]
    var logsById: [UUID: FoodLog]
    var mealItemsById: [UUID: MealItem]
    var targetsById: [UUID: NutritionTarget]
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

private struct NutritionBackupPayloadV2: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let userId: UUID
    let foodItems: [FoodItemBackupDTO]
    let mealRecipes: [MealRecipeBackupDTO]
    let mealRecipeItems: [MealRecipeItemBackupDTO]
    let nutritionLogEntries: [NutritionLogEntryBackupDTO]
    let nutritionTargets: [NutritionTargetBackupDTO]
}

private struct FoodItemBackupDTO: Codable {
    let id: UUID
    let userId: UUID
    let name: String
    let brand: String?
    let referenceLabel: String?
    let referenceQuantity: Double
    let caloriesPerReference: Double
    let proteinPerReference: Double
    let carbsPerReference: Double
    let fatPerReference: Double
    let extraNutrients: [String: Double]?
    let isArchived: Bool
    let isFavorite: Bool
    let kindRaw: Int
    let unitRaw: Int
    let createdAt: Date
    let updatedAt: Date

    init(_ item: FoodItem) {
        id = item.id
        userId = item.userId
        name = item.name
        brand = item.brand
        referenceLabel = item.referenceLabel
        referenceQuantity = item.referenceQuantity
        caloriesPerReference = item.caloriesPerReference
        proteinPerReference = item.proteinPerReference
        carbsPerReference = item.carbsPerReference
        fatPerReference = item.fatPerReference
        extraNutrients = item.extraNutrients
        isArchived = item.isArchived
        isFavorite = item.isFavorite
        kindRaw = item.kindRaw
        unitRaw = item.unitRaw
        createdAt = item.createdAt
        updatedAt = item.updatedAt
    }
}

private struct MealRecipeBackupDTO: Codable {
    let id: UUID
    let userId: UUID
    let name: String
    let batchSize: Double
    let servingUnitLabel: String?
    let defaultCategoryRaw: Int
    let cachedExtraNutrients: [String: Double]?
    let isArchived: Bool
    let createdAt: Date
    let updatedAt: Date

    init(_ recipe: MealRecipe) {
        id = recipe.id
        userId = recipe.userId
        name = recipe.name
        batchSize = recipe.batchSize
        servingUnitLabel = recipe.servingUnitLabel
        defaultCategoryRaw = recipe.defaultCategoryRaw
        cachedExtraNutrients = recipe.cachedExtraNutrients
        isArchived = recipe.isArchived
        createdAt = recipe.createdAt
        updatedAt = recipe.updatedAt
    }
}

private struct MealRecipeItemBackupDTO: Codable {
    let id: UUID
    let mealRecipeId: UUID?
    let foodItemId: UUID
    let amount: Double
    let amountUnitRaw: Int
    let order: Int

    init(_ item: MealRecipeItem) {
        id = item.id
        mealRecipeId = item.mealRecipe?.id
        foodItemId = item.foodItem.id
        amount = item.amount
        amountUnitRaw = item.amountUnitRaw
        order = item.order
    }
}

private struct NutritionLogEntryBackupDTO: Codable {
    let id: UUID
    let userId: UUID
    let timestamp: Date
    let logTypeRaw: Int
    let sourceItemId: UUID?
    let sourceMealId: UUID?
    let amount: Double
    let amountUnitSnapshot: String
    let categoryRaw: Int
    let note: String?
    let dayKey: String
    let logDate: Date
    let creationMethodRaw: Int
    let nameSnapshot: String
    let brandSnapshot: String?
    let servingUnitLabelSnapshot: String?
    let caloriesSnapshot: Double
    let proteinSnapshot: Double
    let carbsSnapshot: Double
    let fatSnapshot: Double
    let extraNutrientsSnapshot: [String: Double]?
    let recipeItemsSnapshot: [RecipeItemSnapshot]?
    let createdAt: Date
    let updatedAt: Date

    init(_ log: NutritionLogEntry) {
        id = log.id
        userId = log.userId
        timestamp = log.timestamp
        logTypeRaw = log.logTypeRaw
        sourceItemId = log.sourceItemId
        sourceMealId = log.sourceMealId
        amount = log.amount
        amountUnitSnapshot = log.amountUnitSnapshot
        categoryRaw = log.categoryRaw
        note = log.note
        dayKey = log.dayKey
        logDate = log.logDate
        creationMethodRaw = log.creationMethodRaw
        nameSnapshot = log.nameSnapshot
        brandSnapshot = log.brandSnapshot
        servingUnitLabelSnapshot = log.servingUnitLabelSnapshot
        caloriesSnapshot = log.caloriesSnapshot
        proteinSnapshot = log.proteinSnapshot
        carbsSnapshot = log.carbsSnapshot
        fatSnapshot = log.fatSnapshot
        extraNutrientsSnapshot = log.extraNutrientsSnapshot
        recipeItemsSnapshot = log.recipeItemsSnapshot
        createdAt = log.createdAt
        updatedAt = log.updatedAt
    }
}

