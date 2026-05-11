import AppIntents
import Foundation
import SwiftData
import WidgetKit

enum NutritionIntentCategory: String, AppEnum, CaseIterable {
    case breakfast
    case lunch
    case dinner
    case snack
    case other

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Nutrition Category")
    static var caseDisplayRepresentations: [NutritionIntentCategory: DisplayRepresentation] = [
        .breakfast: "Breakfast",
        .lunch: "Lunch",
        .dinner: "Dinner",
        .snack: "Snack",
        .other: "Other"
    ]

    var foodLogCategory: FoodLogCategory {
        switch self {
        case .breakfast:
            return .breakfast
        case .lunch:
            return .lunch
        case .dinner:
            return .dinner
        case .snack:
            return .snack
        case .other:
            return .other
        }
    }
}

struct LogNutritionQuickAddIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Nutrition"
    static var description = IntentDescription("Quick add consumed nutrition values.")
    static var openAppWhenRun = false

    @Parameter(title: "Calories")
    var calories: Double?

    @Parameter(title: "Protein")
    var protein: Double?

    @Parameter(title: "Carbohydrates")
    var carbs: Double?

    @Parameter(title: "Fat")
    var fat: Double?

    @Parameter(title: "Fiber")
    var fiber: Double?

    @Parameter(title: "Sodium")
    var sodium: Double?

    @Parameter(title: "Total Sugars")
    var totalSugars: Double?

    @Parameter(title: "Custom Nutrient")
    var customNutrientName: String?

    @Parameter(title: "Custom Nutrient Amount")
    var customNutrientAmount: Double?

    @Parameter(title: "Category", default: .other)
    var category: NutritionIntentCategory

    @Parameter(title: "Note")
    var note: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try NutritionIntentStore.logQuickAdd(
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            fiber: fiber,
            sodium: sodium,
            totalSugars: totalSugars,
            customNutrientName: customNutrientName,
            customNutrientAmount: customNutrientAmount,
            category: category.foodLogCategory,
            note: note
        )
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "Logged \(result.summary).")
    }
}

struct NutritionAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogNutritionQuickAddIntent(),
            phrases: [
                "Log nutrition in \(.applicationName)",
                "Quick add nutrition in \(.applicationName)",
                "Add calories to \(.applicationName)"
            ],
            shortTitle: "Log Nutrition",
            systemImageName: "fork.knife"
        )
    }
}

@MainActor
private enum NutritionIntentStore {
    struct LogResult {
        let summary: String
    }

    enum IntentError: LocalizedError {
        case noAccount
        case noValues
        case negativeValue(String)
        case missingCustomName
        case missingCustomAmount
        case invalidCustomName
        case reservedCustomName(String)

        var errorDescription: String? {
            switch self {
            case .noAccount:
                return "Create or sign in to an account before logging nutrition."
            case .noValues:
                return "Add at least one nutrition value before logging."
            case .negativeValue(let name):
                return "\(name) cannot be negative."
            case .missingCustomName:
                return "Add a custom nutrient name, or remove the custom nutrient amount."
            case .missingCustomAmount:
                return "Add an amount for the custom nutrient."
            case .invalidCustomName:
                return "Custom nutrient name must include at least one letter or number."
            case .reservedCustomName(let name):
                return "Use the dedicated \(name) field instead of Custom Nutrient."
            }
        }
    }

    static func logQuickAdd(
        calories: Double?,
        protein: Double?,
        carbs: Double?,
        fat: Double?,
        fiber: Double?,
        sodium: Double?,
        totalSugars: Double?,
        customNutrientName: String?,
        customNutrientAmount: Double?,
        category: FoodLogCategory,
        note: String?
    ) throws -> LogResult {
        try validateNonNegative("Calories", calories)
        try validateNonNegative("Protein", protein)
        try validateNonNegative("Carbohydrates", carbs)
        try validateNonNegative("Fat", fat)
        try validateNonNegative("Fiber", fiber)
        try validateNonNegative("Sodium", sodium)
        try validateNonNegative("Total Sugars", totalSugars)
        try validateNonNegative("Custom Nutrient Amount", customNutrientAmount)

        let extras = try extraNutrients(
            fiber: fiber,
            sodium: sodium,
            totalSugars: totalSugars,
            customNutrientName: customNutrientName,
            customNutrientAmount: customNutrientAmount
        )
        guard hasAnyProvidedValue(calories, protein, carbs, fat, extras: extras) else {
            throw IntentError.noValues
        }

        let container = SharedModelConfig.createSharedModelContainer()
        let context = ModelContext(container)
        let user = try currentUser(in: context)
        try NutritionDataBackfillService(context: context).backfill(userId: user.id)

        let repository = LocalNutritionRepository(modelContext: context)
        let service = NutritionService(context: context, repository: repository)
        service.currentUser = user

        _ = try service.addQuickNutritionLog(
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            extraNutrients: extras,
            timestamp: Date(),
            category: category,
            note: normalizedOptionalText(note)
        )

        return LogResult(summary: summary(calories: calories, protein: protein, carbs: carbs, fat: fat, extras: extras))
    }

    private static func currentUser(in context: ModelContext) throws -> User {
        let descriptor = FetchDescriptor<User>(
            sortBy: [SortDescriptor(\.lastLogin, order: .reverse)]
        )
        let users = try context.fetch(descriptor).filter { !$0.soft_deleted }
        guard let user = users.first else {
            throw IntentError.noAccount
        }
        return user
    }

    private static func extraNutrients(
        fiber: Double?,
        sodium: Double?,
        totalSugars: Double?,
        customNutrientName: String?,
        customNutrientAmount: Double?
    ) throws -> [String: Double]? {
        var extras: [String: Double] = [:]
        if let fiber {
            extras["fiber"] = max(0, fiber)
        }
        if let sodium {
            extras["sodium"] = max(0, sodium)
        }
        if let totalSugars {
            extras["total-sugars"] = max(0, totalSugars)
        }

        let customName = normalizedOptionalText(customNutrientName)
        if customName == nil, customNutrientAmount != nil {
            throw IntentError.missingCustomName
        }
        if customName != nil, customNutrientAmount == nil {
            throw IntentError.missingCustomAmount
        }
        if let customName, let customNutrientAmount {
            let key = NutritionNutrientKey.normalized(customName)
            guard !key.isEmpty else {
                throw IntentError.invalidCustomName
            }
            if NutritionNutrientKey.coreKeySet.contains(key) {
                throw IntentError.reservedCustomName(customName)
            }
            extras[key] = max(0, customNutrientAmount)
        }

        return extras.isEmpty ? nil : extras
    }

    private static func hasAnyProvidedValue(
        _ values: Double?...,
        extras: [String: Double]?
    ) -> Bool {
        values.contains { $0 != nil } || extras?.isEmpty == false
    }

    private static func validateNonNegative(_ name: String, _ value: Double?) throws {
        guard let value else { return }
        if value < 0 {
            throw IntentError.negativeValue(name)
        }
    }

    private static func normalizedOptionalText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func summary(
        calories: Double?,
        protein: Double?,
        carbs: Double?,
        fat: Double?,
        extras: [String: Double]?
    ) -> String {
        var parts: [String] = []
        if let calories {
            parts.append("\(displayAmount(calories)) kcal")
        }
        if let protein {
            parts.append("\(displayAmount(protein))g protein")
        }
        if let carbs {
            parts.append("\(displayAmount(carbs))g carbs")
        }
        if let fat {
            parts.append("\(displayAmount(fat))g fat")
        }
        for (key, value) in (extras ?? [:]).sorted(by: { $0.key < $1.key }) {
            parts.append("\(displayAmount(value)) \(key.replacingOccurrences(of: "-", with: " "))")
        }
        return parts.isEmpty ? "nutrition" : parts.joined(separator: ", ")
    }

    private static func displayAmount(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return SetDisplayFormatter.formatDecimal(value)
    }
}
