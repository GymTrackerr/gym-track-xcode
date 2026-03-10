import Foundation
import SwiftData

enum FoodKind: Int, Codable, CaseIterable, Identifiable {
    case food = 0
    case drink = 1

    var id: Int { rawValue }
}

enum FoodUnit: Int, Codable, CaseIterable, Identifiable {
    case grams = 0
    case milliliters = 1

    var id: Int { rawValue }

    var shortLabel: String {
        switch self {
        case .grams:
            return "g"
        case .milliliters:
            return "ml"
        }
    }

    var displayName: String {
        switch self {
        case .grams:
            return "Grams"
        case .milliliters:
            return "Milliliters"
        }
    }
}

@Model
final class Food {
    var id: UUID = UUID()
    var userId: UUID
    var name: String
    var brand: String?
    var referenceLabel: String?
    var gramsPerReference: Double
    var kcalPerReference: Double
    var proteinPerReference: Double
    var carbPerReference: Double
    var fatPerReference: Double
    var isArchived: Bool
    var isFavorite: Bool
    var kindRaw: Int
    var unitRaw: Int
    var createdAt: Date
    var updatedAt: Date

    @Relationship(inverse: \FoodLog.food)
    var logs: [FoodLog]

    var kcalPerGram: Double {
        guard gramsPerReference > 0 else { return 0 }
        return kcalPerReference / gramsPerReference
    }

    var proteinPerGram: Double {
        guard gramsPerReference > 0 else { return 0 }
        return proteinPerReference / gramsPerReference
    }

    var carbPerGram: Double {
        guard gramsPerReference > 0 else { return 0 }
        return carbPerReference / gramsPerReference
    }

    var fatPerGram: Double {
        guard gramsPerReference > 0 else { return 0 }
        return fatPerReference / gramsPerReference
    }

    var kind: FoodKind {
        get { FoodKind(rawValue: kindRaw) ?? .food }
        set { kindRaw = newValue.rawValue }
    }

    var unit: FoodUnit {
        get { FoodUnit(rawValue: unitRaw) ?? .grams }
        set { unitRaw = newValue.rawValue }
    }

    init(
        userId: UUID,
        name: String,
        brand: String? = nil,
        referenceLabel: String? = nil,
        gramsPerReference: Double,
        kcalPerReference: Double,
        proteinPerReference: Double,
        carbPerReference: Double,
        fatPerReference: Double,
        isArchived: Bool = false,
        isFavorite: Bool = false,
        kind: FoodKind = .food,
        unit: FoodUnit = .grams
    ) {
        self.userId = userId
        self.name = name
        self.brand = brand
        self.referenceLabel = referenceLabel
        self.gramsPerReference = max(gramsPerReference, 0.1)
        self.kcalPerReference = max(kcalPerReference, 0)
        self.proteinPerReference = max(proteinPerReference, 0)
        self.carbPerReference = max(carbPerReference, 0)
        self.fatPerReference = max(fatPerReference, 0)
        self.isArchived = isArchived
        self.isFavorite = isFavorite
        self.kindRaw = kind.rawValue
        self.unitRaw = unit.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
        self.logs = []
    }

    func update(
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
    ) {
        self.name = name
        self.brand = brand
        self.referenceLabel = referenceLabel
        self.gramsPerReference = max(gramsPerReference, 0.1)
        self.kcalPerReference = max(kcalPerReference, 0)
        self.proteinPerReference = max(proteinPerReference, 0)
        self.carbPerReference = max(carbPerReference, 0)
        self.fatPerReference = max(fatPerReference, 0)
        if let kind {
            self.kind = kind
        }
        if let unit {
            self.unit = unit
        }
        self.updatedAt = Date()
    }
}
