import Foundation
import SwiftData

@Model
final class FoodItem {
    var id: UUID = UUID()
    var userId: UUID
    var name: String
    var brand: String?
    var referenceLabel: String?
    var referenceQuantity: Double
    var servingQuantity: Double?
    var servingUnitLabel: String?
    var labelProfileRaw: String?
    var caloriesPerReference: Double
    var proteinPerReference: Double
    var carbsPerReference: Double
    var fatPerReference: Double
    var extraNutrientsData: Data?
    var providedNutrientKeysData: Data?
    var isArchived: Bool
    var isFavorite: Bool
    var kindRaw: Int
    var unitRaw: Int
    var soft_deleted: Bool = false
    var syncMetaId: UUID?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(inverse: \MealRecipeItem.foodItem)
    var recipeItems: [MealRecipeItem]

    init(
        userId: UUID,
        name: String,
        brand: String? = nil,
        referenceLabel: String? = nil,
        referenceQuantity: Double,
        servingQuantity: Double? = nil,
        servingUnitLabel: String? = nil,
        labelProfile: NutritionLabelProfile? = nil,
        caloriesPerReference: Double,
        proteinPerReference: Double,
        carbsPerReference: Double,
        fatPerReference: Double,
        extraNutrients: [String: Double]? = nil,
        providedNutrientKeys: Set<String>? = nil,
        isArchived: Bool = false,
        isFavorite: Bool = false,
        kind: FoodItemKind = .food,
        unit: FoodItemUnit = .grams
    ) {
        let timestamp = Date()
        self.userId = userId
        self.name = name
        self.brand = brand
        self.referenceLabel = referenceLabel
        self.referenceQuantity = max(0.0001, referenceQuantity)
        self.servingQuantity = servingQuantity.map { max(0.0001, $0) }
        self.servingUnitLabel = servingUnitLabel
        self.labelProfileRaw = labelProfile?.rawValue
        self.caloriesPerReference = max(0, caloriesPerReference)
        self.proteinPerReference = max(0, proteinPerReference)
        self.carbsPerReference = max(0, carbsPerReference)
        self.fatPerReference = max(0, fatPerReference)
        self.extraNutrientsData = CodableJSONHelper.encode(extraNutrients)
        let initialKeys = providedNutrientKeys ?? NutritionNutrientKey.coreKeySet
        self.providedNutrientKeysData = CodableJSONHelper.encode(Array(initialKeys).sorted())
        self.isArchived = isArchived
        self.isFavorite = isFavorite
        self.kindRaw = kind.rawValue
        self.unitRaw = unit.rawValue
        self.soft_deleted = isArchived
        self.syncMetaId = nil
        self.createdAt = timestamp
        self.updatedAt = timestamp
        self.recipeItems = []
    }

    var kind: FoodItemKind {
        get { FoodItemKind(rawValue: kindRaw) ?? .food }
        set { kindRaw = newValue.rawValue }
    }

    var unit: FoodItemUnit {
        get { FoodItemUnit(rawValue: unitRaw) ?? .grams }
        set { unitRaw = newValue.rawValue }
    }

    var extraNutrients: [String: Double]? {
        get { CodableJSONHelper.decode(extraNutrientsData) }
        set { extraNutrientsData = CodableJSONHelper.encode(newValue) }
    }

    var labelProfile: NutritionLabelProfile? {
        get {
            NutritionLabelProfile.storedValue(labelProfileRaw)
        }
        set {
            labelProfileRaw = newValue?.rawValue
        }
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

    var caloriesPerUnit: Double {
        guard referenceQuantity > 0 else { return 0 }
        return caloriesPerReference / referenceQuantity
    }

    var proteinPerUnit: Double {
        guard referenceQuantity > 0 else { return 0 }
        return proteinPerReference / referenceQuantity
    }

    var carbsPerUnit: Double {
        guard referenceQuantity > 0 else { return 0 }
        return carbsPerReference / referenceQuantity
    }

    var fatPerUnit: Double {
        guard referenceQuantity > 0 else { return 0 }
        return fatPerReference / referenceQuantity
    }
}

extension FoodItem: SyncTrackedRoot {
    static var syncModelType: SyncModelType { .foodItem }
    var syncLinkedItemId: String { id.uuidString.lowercased() }
    var syncSeedDate: Date { createdAt }
    var legacyDeleteBridgeValue: Bool? { isArchived }

    func applyLegacyDeleteBridge(_ value: Bool) {
        isArchived = value
    }
}
