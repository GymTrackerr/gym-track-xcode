import Foundation

struct DemoRangeOption: Codable, Hashable, Identifiable {
    let id: String
    let label: String
    let days: Int
}

struct DemoNoisePreset: Codable, Hashable, Identifiable {
    let id: String
    let label: String
    let healthScale: Double
    let sessionScale: Double
    let nutritionScale: Double
}

struct DemoMetricTargetPreset: Codable, Hashable {
    let mean: Double
    let range: Double
}

struct DemoHealthTargetPresets: Codable, Hashable {
    let steps: DemoMetricTargetPreset
    let activeEnergyKcal: DemoMetricTargetPreset
    let exerciseMinutes: DemoMetricTargetPreset
    let restingEnergyKcal: DemoMetricTargetPreset
    let sleepHours: DemoMetricTargetPreset
    let bodyWeightKg: DemoMetricTargetPreset
    let nutritionCalories: DemoMetricTargetPreset
}

struct DemoPresetsBundle: Codable {
    let healthRanges: [DemoRangeOption]
    let sessionRanges: [DemoRangeOption]
    let nutritionRanges: [DemoRangeOption]
    let noiseLevels: [DemoNoisePreset]
    let exerciseMatching: DemoExerciseMatchingPreset
    let defaultHealthRangeId: String
    let defaultSessionRangeId: String
    let defaultNutritionRangeId: String
    let defaultNoiseId: String
    let defaultTargets: DemoHealthTargetPresets
}

struct DemoExerciseMatchingPreset: Codable, Hashable {
    let preferNpIdMatches: Bool
    let allowKeywordFallback: Bool
    let allowTypeFallback: Bool
}

struct DemoRoutineTemplateBundle: Codable {
    let routines: [DemoRoutineTemplate]
}

struct DemoRoutineTemplate: Codable, Identifiable {
    let id: String
    let name: String
    let sessionNotes: [String]
    let slots: [DemoRoutineSlotTemplate]
}

struct DemoRoutineSlotTemplate: Codable, Identifiable {
    let id: String
    let label: String
    let preferredNpIds: [String]?
    let keywords: [String]
    let fallbackTypes: [String]
    let style: String
    let sets: Int
    let repRange: [Int]?
    let weightBase: Double?
    let weightStep: Double?
    let durationMinutesRange: [Int]?
    let distanceRange: [Double]?
    let distanceUnit: String?
}

struct DemoNutritionTemplateBundle: Codable {
    let foods: [DemoFoodTemplate]
    let meals: [DemoMealTemplate]
    let target: DemoNutritionTargetTemplate
    let patterns: DemoNutritionPatterns
}

struct DemoFoodTemplate: Codable, Identifiable {
    let id: String
    let name: String
    let brand: String?
    let referenceLabel: String?
    let referenceQuantity: Double
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let kind: String
    let unit: String
    let favorite: Bool?
}

struct DemoMealTemplate: Codable, Identifiable {
    let id: String
    let name: String
    let defaultCategory: String
    let batchSize: Double
    let servingUnitLabel: String?
    let items: [DemoMealItemTemplate]
}

struct DemoMealItemTemplate: Codable {
    let foodId: String
    let amount: Double
}

struct DemoNutritionTargetTemplate: Codable {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
}

struct DemoNutritionPatterns: Codable {
    let weekday: [DemoMealSlotPattern]
    let weekend: [DemoMealSlotPattern]
}

struct DemoMealSlotPattern: Codable, Identifiable {
    let id: String
    let category: String
    let mealIds: [String]
    let amountRange: [Double]
    let probability: Double
    let noteOptions: [String]?
}

struct DemoMetricTargetSetting: Hashable {
    var mean: Double
    var range: Double
}

struct DemoHealthTargetSettings: Hashable {
    var steps: DemoMetricTargetSetting
    var activeEnergyKcal: DemoMetricTargetSetting
    var exerciseMinutes: DemoMetricTargetSetting
    var restingEnergyKcal: DemoMetricTargetSetting
    var sleepHours: DemoMetricTargetSetting
    var bodyWeightKg: DemoMetricTargetSetting
    var nutritionCalories: DemoMetricTargetSetting

    init(presets: DemoHealthTargetPresets) {
        self.steps = DemoMetricTargetSetting(mean: presets.steps.mean, range: presets.steps.range)
        self.activeEnergyKcal = DemoMetricTargetSetting(mean: presets.activeEnergyKcal.mean, range: presets.activeEnergyKcal.range)
        self.exerciseMinutes = DemoMetricTargetSetting(mean: presets.exerciseMinutes.mean, range: presets.exerciseMinutes.range)
        self.restingEnergyKcal = DemoMetricTargetSetting(mean: presets.restingEnergyKcal.mean, range: presets.restingEnergyKcal.range)
        self.sleepHours = DemoMetricTargetSetting(mean: presets.sleepHours.mean, range: presets.sleepHours.range)
        self.bodyWeightKg = DemoMetricTargetSetting(mean: presets.bodyWeightKg.mean, range: presets.bodyWeightKg.range)
        self.nutritionCalories = DemoMetricTargetSetting(mean: presets.nutritionCalories.mean, range: presets.nutritionCalories.range)
    }
}

struct DemoSeedConfiguration: Hashable {
    var demoUserName: String
    var healthRange: DemoRangeOption
    var sessionRange: DemoRangeOption
    var nutritionRange: DemoRangeOption
    var noise: DemoNoisePreset
    var healthTargets: DemoHealthTargetSettings
}

extension DemoSeedConfiguration {
    init(profile: DemoSeedProfile, presets: DemoPresetsBundle) {
        self.demoUserName = profile.demoUserName
        self.healthRange = presets.healthRange(id: profile.healthRangeId) ?? presets.fallbackHealthRange
        self.sessionRange = presets.sessionRange(id: profile.sessionRangeId) ?? presets.fallbackSessionRange
        self.nutritionRange = presets.nutritionRange(id: profile.nutritionRangeId) ?? presets.fallbackNutritionRange
        self.noise = presets.noiseLevel(id: profile.noiseId) ?? presets.fallbackNoise
        self.healthTargets = DemoHealthTargetSettings(
            steps: DemoMetricTargetSetting(mean: profile.stepsMean, range: profile.stepsRange),
            activeEnergyKcal: DemoMetricTargetSetting(mean: profile.activeEnergyMean, range: profile.activeEnergyRange),
            exerciseMinutes: DemoMetricTargetSetting(mean: profile.exerciseMinutesMean, range: profile.exerciseMinutesRange),
            restingEnergyKcal: DemoMetricTargetSetting(mean: profile.restingEnergyMean, range: profile.restingEnergyRange),
            sleepHours: DemoMetricTargetSetting(mean: profile.sleepHoursMean, range: profile.sleepHoursRange),
            bodyWeightKg: DemoMetricTargetSetting(mean: profile.bodyWeightMean, range: profile.bodyWeightRange),
            nutritionCalories: DemoMetricTargetSetting(mean: profile.nutritionCaloriesMean, range: profile.nutritionCaloriesRange)
        )
    }
}

extension DemoHealthTargetSettings {
    init(
        steps: DemoMetricTargetSetting,
        activeEnergyKcal: DemoMetricTargetSetting,
        exerciseMinutes: DemoMetricTargetSetting,
        restingEnergyKcal: DemoMetricTargetSetting,
        sleepHours: DemoMetricTargetSetting,
        bodyWeightKg: DemoMetricTargetSetting,
        nutritionCalories: DemoMetricTargetSetting
    ) {
        self.steps = steps
        self.activeEnergyKcal = activeEnergyKcal
        self.exerciseMinutes = exerciseMinutes
        self.restingEnergyKcal = restingEnergyKcal
        self.sleepHours = sleepHours
        self.bodyWeightKg = bodyWeightKg
        self.nutritionCalories = nutritionCalories
    }
}

extension DemoPresetsBundle {
    var fallbackHealthRange: DemoRangeOption {
        healthRange(id: defaultHealthRangeId) ?? healthRanges.first!
    }

    var fallbackSessionRange: DemoRangeOption {
        sessionRange(id: defaultSessionRangeId) ?? sessionRanges.first!
    }

    var fallbackNutritionRange: DemoRangeOption {
        nutritionRange(id: defaultNutritionRangeId) ?? nutritionRanges.first!
    }

    var fallbackNoise: DemoNoisePreset {
        noiseLevel(id: defaultNoiseId) ?? noiseLevels.first!
    }

    func defaultConfiguration(demoUserName: String = "Demo") -> DemoSeedConfiguration {
        DemoSeedConfiguration(
            demoUserName: demoUserName,
            healthRange: fallbackHealthRange,
            sessionRange: fallbackSessionRange,
            nutritionRange: fallbackNutritionRange,
            noise: fallbackNoise,
            healthTargets: DemoHealthTargetSettings(presets: defaultTargets)
        )
    }

    func healthRange(id: String) -> DemoRangeOption? {
        healthRanges.first(where: { $0.id == id })
    }

    func sessionRange(id: String) -> DemoRangeOption? {
        sessionRanges.first(where: { $0.id == id })
    }

    func nutritionRange(id: String) -> DemoRangeOption? {
        nutritionRanges.first(where: { $0.id == id })
    }

    func noiseLevel(id: String) -> DemoNoisePreset? {
        noiseLevels.first(where: { $0.id == id })
    }
}

struct DemoSeedSummary {
    let exerciseCount: Int
    let routineCount: Int
    let sessionCount: Int
    let mealCount: Int
    let logCount: Int
    let healthDayCount: Int
}

enum DemoSeedError: LocalizedError {
    case missingSourceUser
    case missingSourceExercises
    case missingTemplate(String)
    case invalidTemplate(String)

    var errorDescription: String? {
        switch self {
        case .missingSourceUser:
            return "No non-demo account is available to clone exercises from."
        case .missingSourceExercises:
            return "The source account does not have any exercises to clone into demo mode."
        case .missingTemplate(let name):
            return "Could not find bundled demo template '\(name)'."
        case .invalidTemplate(let name):
            return "The bundled demo template '\(name)' could not be decoded."
        }
    }
}

enum DemoTemplateLoader {
    static func loadPresets() throws -> DemoPresetsBundle {
        try load("demo_presets", as: DemoPresetsBundle.self)
    }

    static func loadRoutines() throws -> DemoRoutineTemplateBundle {
        try load("demo_routines", as: DemoRoutineTemplateBundle.self)
    }

    static func loadNutrition() throws -> DemoNutritionTemplateBundle {
        try load("demo_nutrition", as: DemoNutritionTemplateBundle.self)
    }

    private static func load<T: Decodable>(_ resource: String, as type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys

        let candidateURLs: [URL?] = [
            Bundle.main.url(forResource: resource, withExtension: "json", subdirectory: "Features/User/demo"),
            Bundle.main.url(forResource: resource, withExtension: "json")
        ]

        guard let url = candidateURLs.compactMap({ $0 }).first else {
            throw DemoSeedError.missingTemplate(resource)
        }

        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(T.self, from: data)
        } catch let error as DemoSeedError {
            throw error
        } catch {
            throw DemoSeedError.invalidTemplate(resource)
        }
    }
}

extension FoodLogCategory {
    static func demoValue(from rawValue: String) -> FoodLogCategory {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "breakfast":
            return .breakfast
        case "lunch":
            return .lunch
        case "dinner":
            return .dinner
        case "snack":
            return .snack
        default:
            return .other
        }
    }
}

extension FoodItemKind {
    static func demoValue(from rawValue: String) -> FoodItemKind {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "drink":
            return .drink
        case "ingredient":
            return .ingredient
        default:
            return .food
        }
    }
}

extension FoodItemUnit {
    static func demoValue(from rawValue: String) -> FoodItemUnit {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ml", "milliliter", "milliliters":
            return .milliliters
        case "piece", "pc":
            return .piece
        default:
            return .grams
        }
    }
}
