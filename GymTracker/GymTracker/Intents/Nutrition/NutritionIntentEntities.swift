import AppIntents
import Foundation

struct NutritionFoodEntity: AppEntity {
    static let defaultQuery = NutritionFoodEntityQuery()
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource(
        "nutrition.entity.food",
        defaultValue: "Food",
        table: "Nutrition",
        comment: "Display name for a food entity in App Intents."
    ))

    var id: UUID
    var name: String
    var subtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(subtitle)")
    }
}

struct NutritionFoodEntityQuery: EntityStringQuery {
    func entities(for identifiers: [NutritionFoodEntity.ID]) async throws -> [NutritionFoodEntity] {
        try await MainActor.run {
            try NutritionIntentStore.foodEntities(identifiers: identifiers)
        }
    }

    func entities(matching string: String) async throws -> [NutritionFoodEntity] {
        try await MainActor.run {
            try NutritionIntentStore.foodEntities(matching: string)
        }
    }

    func suggestedEntities() async throws -> [NutritionFoodEntity] {
        try await MainActor.run {
            try NutritionIntentStore.suggestedFoodEntities()
        }
    }
}

struct NutritionMealEntity: AppEntity {
    static let defaultQuery = NutritionMealEntityQuery()
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource(
        "nutrition.entity.meal",
        defaultValue: "Meal",
        table: "Nutrition",
        comment: "Display name for a meal entity in App Intents."
    ))

    var id: UUID
    var name: String
    var subtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(subtitle)")
    }
}

struct NutritionMealEntityQuery: EntityStringQuery {
    func entities(for identifiers: [NutritionMealEntity.ID]) async throws -> [NutritionMealEntity] {
        try await MainActor.run {
            try NutritionIntentStore.mealEntities(identifiers: identifiers)
        }
    }

    func entities(matching string: String) async throws -> [NutritionMealEntity] {
        try await MainActor.run {
            try NutritionIntentStore.mealEntities(matching: string)
        }
    }

    func suggestedEntities() async throws -> [NutritionMealEntity] {
        try await MainActor.run {
            try NutritionIntentStore.suggestedMealEntities()
        }
    }
}
