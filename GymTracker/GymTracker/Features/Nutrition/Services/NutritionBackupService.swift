import Foundation
import SwiftData

@MainActor
final class NutritionBackupService {
    enum BackupError: LocalizedError {
        case missingUser
        case invalidSchemaVersion(Int)
        case invalidBackup(String)
        case persistence(String)

        var errorDescription: String? {
            switch self {
            case .missingUser:
                return "You must be signed in to use nutrition backup."
            case .invalidSchemaVersion(let version):
                return "Unsupported backup schema version: \(version). This app only imports nutrition backups with schemaVersion 2."
            case .invalidBackup(let message):
                return message
            case .persistence(let message):
                return message
            }
        }
    }

    struct ImportResult {
        let targets: Int
        let nutrientDefinitions: Int
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

    func exportNutritionJSON() throws -> URL {
        guard let userId = currentUserProvider()?.id else {
            throw BackupError.missingUser
        }

        let payload = try buildV2Payload(userId: userId)

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

        let data = try readBackupData(from: url)
        let schemaVersion = try decodeSchemaVersion(from: data)
        guard schemaVersion == 2 else {
            throw BackupError.invalidSchemaVersion(schemaVersion)
        }

        do {
            let payload = try decodeV2BackupPayload(from: data)
            let result = try importV2(payload: payload, userId: userId)
            try modelContext.save()
            return result
        } catch let error as BackupError {
            modelContext.rollback()
            throw error
        } catch {
            modelContext.rollback()
            throw BackupError.persistence("Could not import nutrition backup.")
        }
    }

    private func readBackupData(from url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw BackupError.persistence("Could not read backup file.")
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

    private func buildV2Payload(userId: UUID) throws -> NutritionBackupPayloadV2 {
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
        let targets = try fetchTargets(userId: userId)
        let nutrientDefinitions = try fetchNutrientDefinitions(userId: userId)

        return NutritionBackupPayloadV2(
            schemaVersion: 2,
            exportedAt: Date(),
            userId: userId,
            nutrientDefinitions: nutrientDefinitions.map(NutritionNutrientDefinitionBackupDTO.init),
            foodItems: foodItems.map(FoodItemBackupDTO.init),
            mealRecipes: mealRecipes.map(MealRecipeBackupDTO.init),
            mealRecipeItems: mealRecipeItems.map(MealRecipeItemBackupDTO.init),
            nutritionLogEntries: nutritionLogs.map(NutritionLogEntryBackupDTO.init),
            nutritionTargets: targets.map(NutritionTargetBackupDTO.init)
        )
    }

    private func importV2(payload: NutritionBackupPayloadV2, userId: UUID) throws -> ImportResult {
        let existingFoodItems = Dictionary(uniqueKeysWithValues: try fetchFoodItems(userId: userId).map { ($0.id, $0) })
        let existingMealRecipes = Dictionary(uniqueKeysWithValues: try fetchMealRecipes(userId: userId).map { ($0.id, $0) })
        let existingMealRecipeItems = Dictionary(uniqueKeysWithValues: try fetchMealRecipeItems(userId: userId).map { ($0.id, $0) })
        let existingLogs = Dictionary(uniqueKeysWithValues: try fetchNutritionLogEntries(userId: userId).map { ($0.id, $0) })
        let existingTargets = Dictionary(uniqueKeysWithValues: try fetchTargets(userId: userId).map { ($0.id, $0) })
        let existingDefinitions = Dictionary(uniqueKeysWithValues: try fetchNutrientDefinitions(userId: userId).map { ($0.id, $0) })
        let importedDefinitionCount = payload.nutrientDefinitions?.count ?? 0

        for dto in payload.nutrientDefinitions ?? [] {
            let definition = existingDefinitions[dto.id] ?? NutritionNutrientDefinition(
                userId: userId,
                key: dto.key,
                displayName: dto.displayName,
                unitLabel: dto.unitLabel,
                group: dto.group,
                sortOrder: dto.sortOrder,
                dailyGoal: dto.dailyGoal,
                isVisible: dto.isVisible,
                isArchived: dto.isArchived
            )
            if existingDefinitions[dto.id] == nil {
                definition.id = dto.id
                modelContext.insert(definition)
            }
            definition.userId = userId
            definition.key = NutritionNutrientKey.normalized(dto.key)
            definition.displayName = dto.displayName
            definition.unitLabel = dto.unitLabel
            definition.group = dto.group
            definition.sortOrder = dto.sortOrder
            definition.dailyGoal = dto.dailyGoal
            definition.isVisible = dto.isVisible
            definition.isArchived = dto.isArchived
            definition.soft_deleted = dto.softDeleted
            definition.createdAt = dto.createdAt
            definition.updatedAt = dto.updatedAt
        }

        let seededDefinitionCount = try seedMissingBundledNutrientDefinitions(userId: userId)

        var foodItemsById: [UUID: FoodItem] = existingFoodItems
        for dto in payload.foodItems {
            let importedServingUnitLabel = normalizedOptionalText(dto.servingUnitLabel) ?? normalizedOptionalText(dto.referenceLabel)
            let importedServingQuantity = dto.servingQuantity ?? (importedServingUnitLabel == nil ? nil : dto.referenceQuantity)
            let importedExtraNutrients = normalizedExtraNutrients(dto.extraNutrients)
            let importedProvidedKeys = normalizedProvidedKeys(
                dto.providedNutrientKeys,
                fallback: NutritionNutrientKey.coreKeySet,
                extras: importedExtraNutrients
            )
            let item = foodItemsById[dto.id] ?? FoodItem(
                userId: userId,
                name: dto.name,
                brand: dto.brand,
                referenceLabel: dto.referenceLabel,
                referenceQuantity: dto.referenceQuantity,
                servingQuantity: importedServingQuantity,
                servingUnitLabel: importedServingUnitLabel,
                labelProfile: dto.labelProfile,
                caloriesPerReference: dto.caloriesPerReference,
                proteinPerReference: dto.proteinPerReference,
                carbsPerReference: dto.carbsPerReference,
                fatPerReference: dto.fatPerReference,
                extraNutrients: importedExtraNutrients,
                providedNutrientKeys: importedProvidedKeys,
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
            item.servingQuantity = importedServingQuantity.map { max(0.0001, $0) }
            item.servingUnitLabel = importedServingUnitLabel
            item.labelProfile = dto.labelProfile
            item.caloriesPerReference = max(0, dto.caloriesPerReference)
            item.proteinPerReference = max(0, dto.proteinPerReference)
            item.carbsPerReference = max(0, dto.carbsPerReference)
            item.fatPerReference = max(0, dto.fatPerReference)
            item.extraNutrients = importedExtraNutrients
            item.providedNutrientKeys = importedProvidedKeys
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
            let importedCachedExtraNutrients = normalizedExtraNutrients(dto.cachedExtraNutrients)
            let recipe = mealRecipesById[dto.id] ?? MealRecipe(
                userId: userId,
                name: dto.name,
                batchSize: dto.batchSize,
                servingUnitLabel: dto.servingUnitLabel,
                defaultCategory: FoodLogCategory(rawValue: dto.defaultCategoryRaw) ?? .other,
                cachedExtraNutrients: importedCachedExtraNutrients,
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
            recipe.cachedExtraNutrients = importedCachedExtraNutrients
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
            let logType = NutritionLogType(rawValue: dto.logTypeRaw) ?? .food
            let importedExtraNutrients = normalizedExtraNutrients(dto.extraNutrientsSnapshot)
            let importedRecipeItems = normalizedRecipeItemSnapshots(dto.recipeItemsSnapshot)
            let importedProvidedKeys = normalizedProvidedKeys(
                dto.providedNutrientKeys,
                fallback: defaultProvidedKeys(
                    for: logType,
                    calories: dto.caloriesSnapshot,
                    protein: dto.proteinSnapshot,
                    carbs: dto.carbsSnapshot,
                    fat: dto.fatSnapshot
                ),
                extras: importedExtraNutrients
            )
            let draft = NutritionLogDraft(
                logType: logType,
                creationMethod: LogCreationMethod(rawValue: dto.creationMethodRaw) ?? .importedBackup,
                sourceItemId: dto.sourceItemId,
                sourceMealId: dto.sourceMealId,
                nameSnapshot: dto.nameSnapshot,
                brandSnapshot: dto.brandSnapshot,
                amount: dto.amount,
                amountUnitSnapshot: dto.amountUnitSnapshot,
                servingUnitLabelSnapshot: dto.servingUnitLabelSnapshot,
                amountMode: dto.amountMode ?? defaultAmountMode(for: logType),
                servingQuantitySnapshot: dto.servingQuantitySnapshot,
                servingCountSnapshot: dto.servingCountSnapshot,
                caloriesSnapshot: dto.caloriesSnapshot,
                proteinSnapshot: dto.proteinSnapshot,
                carbsSnapshot: dto.carbsSnapshot,
                fatSnapshot: dto.fatSnapshot,
                extraNutrientsSnapshot: importedExtraNutrients,
                recipeItemsSnapshot: importedRecipeItems,
                providedNutrientKeys: importedProvidedKeys,
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
                isEnabled: dto.isEnabled,
                labelProfile: dto.labelProfile ?? .defaultProfile
            )
            if existingTargets[dto.id] == nil {
                target.id = dto.id
                modelContext.insert(target)
            }
            target.userId = userId
            target.createdAt = dto.createdAt
            target.updatedAt = dto.updatedAt
            target.calorieTarget = dto.calorieTarget
            target.proteinTarget = dto.proteinTarget
            target.carbTarget = dto.carbTarget
            target.fatTarget = dto.fatTarget
            target.isEnabled = dto.isEnabled
            target.labelProfile = dto.labelProfile ?? .defaultProfile
        }

        return ImportResult(
            targets: payload.nutritionTargets.count,
            nutrientDefinitions: importedDefinitionCount + seededDefinitionCount,
            foodItems: payload.foodItems.count,
            mealRecipes: payload.mealRecipes.count,
            mealRecipeItems: payload.mealRecipeItems.count,
            nutritionLogEntries: payload.nutritionLogEntries.count
        )
    }

    private func validateDraft(_ draft: NutritionLogDraft) throws {
        if draft.nameSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw BackupError.invalidBackup("Nutrition log entry is missing name snapshot.")
        }
        if draft.amountUnitSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw BackupError.invalidBackup("Nutrition log entry is missing amount unit snapshot.")
        }
        if draft.logType == .quickCalories && draft.providedNutrientKeys.isEmpty {
            throw BackupError.invalidBackup("Quick nutrition log entry has no provided values.")
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
        log.amountMode = draft.amountMode
        log.servingQuantitySnapshot = draft.servingQuantitySnapshot
        log.servingCountSnapshot = draft.servingCountSnapshot
        log.caloriesSnapshot = max(0, draft.caloriesSnapshot)
        log.proteinSnapshot = max(0, draft.proteinSnapshot)
        log.carbsSnapshot = max(0, draft.carbsSnapshot)
        log.fatSnapshot = max(0, draft.fatSnapshot)
        log.extraNutrientsSnapshot = draft.extraNutrientsSnapshot
        log.recipeItemsSnapshot = draft.recipeItemsSnapshot
        log.providedNutrientKeys = draft.providedNutrientKeys
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

    private func normalizedExtraNutrients(_ values: [String: Double]?) -> [String: Double]? {
        guard let values else { return nil }
        let normalized = values.reduce(into: [String: Double]()) { partial, pair in
            let key = NutritionNutrientKey.normalized(pair.key)
            guard !key.isEmpty else { return }
            partial[key] = max(0, pair.value)
        }
        return normalized.isEmpty ? nil : normalized
    }

    private func normalizedProvidedKeys(
        _ keys: Set<String>?,
        fallback: Set<String>,
        extras: [String: Double]?
    ) -> Set<String> {
        var normalized = Set((keys ?? fallback).map(NutritionNutrientKey.normalized).filter { !$0.isEmpty })
        for key in (extras ?? [:]).keys {
            let normalizedKey = NutritionNutrientKey.normalized(key)
            guard !normalizedKey.isEmpty else { continue }
            normalized.insert(normalizedKey)
        }
        return normalized
    }

    private func normalizedRecipeItemSnapshots(_ snapshots: [RecipeItemSnapshot]?) -> [RecipeItemSnapshot]? {
        guard let snapshots else { return nil }
        guard !snapshots.isEmpty else { return nil }
        return snapshots.map { snapshot in
            RecipeItemSnapshot(
                name: snapshot.name,
                amount: snapshot.amount,
                amountUnit: snapshot.amountUnit,
                caloriesSnapshot: max(0, snapshot.caloriesSnapshot),
                proteinSnapshot: max(0, snapshot.proteinSnapshot),
                carbsSnapshot: max(0, snapshot.carbsSnapshot),
                fatSnapshot: max(0, snapshot.fatSnapshot),
                extraNutrientsSnapshot: normalizedExtraNutrients(snapshot.extraNutrientsSnapshot)
            )
        }
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

    private func defaultProvidedKeys(
        for logType: NutritionLogType,
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double
    ) -> Set<String> {
        switch logType {
        case .quickCalories:
            var keys: Set<String> = []
            if calories > 0 { keys.insert(NutritionNutrientKey.calories) }
            if protein > 0 { keys.insert(NutritionNutrientKey.protein) }
            if carbs > 0 { keys.insert(NutritionNutrientKey.carbs) }
            if fat > 0 { keys.insert(NutritionNutrientKey.fat) }
            return keys.isEmpty ? [NutritionNutrientKey.calories] : keys
        case .food, .meal:
            return NutritionNutrientKey.coreKeySet
        }
    }

    private func seedMissingBundledNutrientDefinitions(userId: UUID) throws -> Int {
        let existing = try fetchNutrientDefinitions(userId: userId)
        var existingKeys = Set(existing.map { NutritionNutrientKey.normalized($0.key) })
        var insertedCount = 0

        for preset in NutritionNutrientPreset.defaultPresets() {
            let key = NutritionNutrientKey.normalized(preset.key)
            guard !key.isEmpty, !existingKeys.contains(key) else { continue }

            let definition = NutritionNutrientDefinition(
                userId: userId,
                key: key,
                displayName: preset.displayName,
                unitLabel: preset.unitLabel,
                group: preset.group,
                sortOrder: preset.sortOrder,
                dailyGoal: nil,
                isVisible: true,
                isArchived: false
            )
            modelContext.insert(definition)
            existingKeys.insert(key)
            insertedCount += 1
        }

        return insertedCount
    }

    private func fetchTargets(userId: UUID) throws -> [NutritionTarget] {
        let descriptor = FetchDescriptor<NutritionTarget>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try modelContext.fetch(descriptor).filter { $0.userId == userId || $0.userId == nil }
    }

    private func fetchNutrientDefinitions(userId: UUID) throws -> [NutritionNutrientDefinition] {
        let descriptor = FetchDescriptor<NutritionNutrientDefinition>(
            predicate: #Predicate<NutritionNutrientDefinition> { definition in
                definition.userId == userId
            },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.displayName)]
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

private struct NutritionBackupPayloadV2: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let userId: UUID
    let nutrientDefinitions: [NutritionNutrientDefinitionBackupDTO]?
    let foodItems: [FoodItemBackupDTO]
    let mealRecipes: [MealRecipeBackupDTO]
    let mealRecipeItems: [MealRecipeItemBackupDTO]
    let nutritionLogEntries: [NutritionLogEntryBackupDTO]
    let nutritionTargets: [NutritionTargetBackupDTO]
}

private struct NutritionNutrientDefinitionBackupDTO: Codable {
    let id: UUID
    let userId: UUID
    let key: String
    let displayName: String
    let unitLabel: String
    let group: NutritionNutrientGroup?
    let sortOrder: Int
    let dailyGoal: Double?
    let isVisible: Bool
    let isArchived: Bool
    let softDeleted: Bool
    let createdAt: Date
    let updatedAt: Date

    init(_ definition: NutritionNutrientDefinition) {
        id = definition.id
        userId = definition.userId
        key = definition.key
        displayName = definition.displayName
        unitLabel = definition.unitLabel
        group = definition.group
        sortOrder = definition.sortOrder
        dailyGoal = definition.dailyGoal
        isVisible = definition.isVisible
        isArchived = definition.isArchived
        softDeleted = definition.soft_deleted
        createdAt = definition.createdAt
        updatedAt = definition.updatedAt
    }
}

private struct FoodItemBackupDTO: Codable {
    let id: UUID
    let userId: UUID
    let name: String
    let brand: String?
    let referenceLabel: String?
    let referenceQuantity: Double
    let servingQuantity: Double?
    let servingUnitLabel: String?
    let labelProfile: NutritionLabelProfile?
    let caloriesPerReference: Double
    let proteinPerReference: Double
    let carbsPerReference: Double
    let fatPerReference: Double
    let extraNutrients: [String: Double]?
    let providedNutrientKeys: Set<String>?
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
        servingQuantity = item.servingQuantity
        servingUnitLabel = item.servingUnitLabel
        labelProfile = item.labelProfile
        caloriesPerReference = item.caloriesPerReference
        proteinPerReference = item.proteinPerReference
        carbsPerReference = item.carbsPerReference
        fatPerReference = item.fatPerReference
        extraNutrients = item.extraNutrients
        providedNutrientKeys = item.providedNutrientKeys
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
    let amountMode: NutritionLogAmountMode?
    let servingQuantitySnapshot: Double?
    let servingCountSnapshot: Double?
    let caloriesSnapshot: Double
    let proteinSnapshot: Double
    let carbsSnapshot: Double
    let fatSnapshot: Double
    let extraNutrientsSnapshot: [String: Double]?
    let recipeItemsSnapshot: [RecipeItemSnapshot]?
    let providedNutrientKeys: Set<String>?
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
        amountMode = log.amountMode
        servingQuantitySnapshot = log.servingQuantitySnapshot
        servingCountSnapshot = log.servingCountSnapshot
        caloriesSnapshot = log.caloriesSnapshot
        proteinSnapshot = log.proteinSnapshot
        carbsSnapshot = log.carbsSnapshot
        fatSnapshot = log.fatSnapshot
        extraNutrientsSnapshot = log.extraNutrientsSnapshot
        recipeItemsSnapshot = log.recipeItemsSnapshot
        providedNutrientKeys = log.providedNutrientKeys
        createdAt = log.createdAt
        updatedAt = log.updatedAt
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
    let labelProfile: NutritionLabelProfile?

    init(_ target: NutritionTarget) {
        id = target.id
        createdAt = target.createdAt
        updatedAt = target.updatedAt
        calorieTarget = target.calorieTarget
        proteinTarget = target.proteinTarget
        carbTarget = target.carbTarget
        fatTarget = target.fatTarget
        isEnabled = target.isEnabled
        labelProfile = target.labelProfile
    }
}
