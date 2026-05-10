import Foundation
import SwiftData

@Model
final class NutritionLogEntry {
    var id: UUID = UUID()
    var userId: UUID
    var timestamp: Date
    var logTypeRaw: Int
    var sourceItemId: UUID?
    var sourceMealId: UUID?
    var amount: Double
    var amountUnitSnapshot: String
    var categoryRaw: Int
    var note: String?
    var dayKey: String
    var logDate: Date
    var creationMethodRaw: Int
    var nameSnapshot: String
    var brandSnapshot: String?
    var servingUnitLabelSnapshot: String?
    var amountModeRaw: Int?
    var servingQuantitySnapshot: Double?
    var servingCountSnapshot: Double?
    var caloriesSnapshot: Double
    var proteinSnapshot: Double
    var carbsSnapshot: Double
    var fatSnapshot: Double
    var extraNutrientsSnapshotData: Data?
    var recipeItemsSnapshotData: Data?
    var providedNutrientKeysData: Data?
    var soft_deleted: Bool = false
    var syncMetaId: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        userId: UUID,
        timestamp: Date,
        logType: NutritionLogType,
        sourceItemId: UUID?,
        sourceMealId: UUID?,
        amount: Double,
        amountUnitSnapshot: String,
        category: FoodLogCategory,
        note: String?,
        dayKey: String,
        logDate: Date,
        creationMethod: LogCreationMethod,
        nameSnapshot: String,
        brandSnapshot: String?,
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
        providedNutrientKeys: Set<String>? = nil
    ) {
        let createdTimestamp = Date()
        self.userId = userId
        self.timestamp = timestamp
        self.logTypeRaw = logType.rawValue
        self.sourceItemId = sourceItemId
        self.sourceMealId = sourceMealId
        self.amount = max(0, amount)
        self.amountUnitSnapshot = amountUnitSnapshot
        self.categoryRaw = category.rawValue
        self.note = note
        self.dayKey = dayKey
        self.logDate = logDate
        self.creationMethodRaw = creationMethod.rawValue
        self.nameSnapshot = nameSnapshot
        self.brandSnapshot = brandSnapshot
        self.servingUnitLabelSnapshot = servingUnitLabelSnapshot
        self.amountModeRaw = amountMode?.rawValue
        self.servingQuantitySnapshot = servingQuantitySnapshot.map { max(0, $0) }
        self.servingCountSnapshot = servingCountSnapshot.map { max(0, $0) }
        self.caloriesSnapshot = max(0, caloriesSnapshot)
        self.proteinSnapshot = max(0, proteinSnapshot)
        self.carbsSnapshot = max(0, carbsSnapshot)
        self.fatSnapshot = max(0, fatSnapshot)
        self.extraNutrientsSnapshotData = CodableJSONHelper.encode(extraNutrientsSnapshot)
        self.recipeItemsSnapshotData = CodableJSONHelper.encode(recipeItemsSnapshot)
        let fallbackKeys = providedNutrientKeys ?? NutritionNutrientKey.coreKeySet
        self.providedNutrientKeysData = CodableJSONHelper.encode(Array(fallbackKeys).sorted())
        self.soft_deleted = false
        self.syncMetaId = nil
        self.createdAt = createdTimestamp
        self.updatedAt = createdTimestamp
    }

    var logType: NutritionLogType {
        get { NutritionLogType(rawValue: logTypeRaw) ?? .food }
        set { logTypeRaw = newValue.rawValue }
    }

    var category: FoodLogCategory {
        get { FoodLogCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var creationMethod: LogCreationMethod {
        get { LogCreationMethod(rawValue: creationMethodRaw) ?? .manual }
        set { creationMethodRaw = newValue.rawValue }
    }

    var amountMode: NutritionLogAmountMode {
        get {
            if let amountModeRaw, let amountMode = NutritionLogAmountMode(rawValue: amountModeRaw) {
                return amountMode
            }
            switch logType {
            case .food:
                return .baseUnit
            case .meal:
                return .serving
            case .quickCalories:
                return .quickAdd
            }
        }
        set { amountModeRaw = newValue.rawValue }
    }

    var extraNutrientsSnapshot: [String: Double]? {
        get { CodableJSONHelper.decode(extraNutrientsSnapshotData) }
        set { extraNutrientsSnapshotData = CodableJSONHelper.encode(newValue) }
    }

    var recipeItemsSnapshot: [RecipeItemSnapshot]? {
        get { CodableJSONHelper.decode(recipeItemsSnapshotData) }
        set { recipeItemsSnapshotData = CodableJSONHelper.encode(newValue) }
    }

    var providedNutrientKeys: Set<String> {
        get {
            guard let decoded: [String] = CodableJSONHelper.decode(providedNutrientKeysData) else {
                return NutritionNutrientKey.coreKeySet
            }
            return Set(decoded.map(Self.normalizedNutrientKey))
        }
        set {
            providedNutrientKeysData = CodableJSONHelper.encode(Array(newValue).sorted())
        }
    }

    func hasProvidedNutrient(_ key: String) -> Bool {
        providedNutrientKeys.contains(Self.normalizedNutrientKey(key))
    }

    private static func normalizedNutrientKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }
}

extension NutritionLogEntry: SyncTrackedRoot {
    static var syncModelType: SyncModelType { .nutritionLogEntry }
    var syncLinkedItemId: String { id.uuidString.lowercased() }
    var syncSeedDate: Date { createdAt }
}
