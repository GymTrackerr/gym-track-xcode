import Foundation

struct NutritionWidgetGoalSnapshot: Codable, Hashable, Identifiable {
    var id: String { key }

    let key: String
    let name: String
    let value: Double
    let target: Double
    let unit: String

    var progress: Double {
        guard target > 0 else { return 0 }
        return min(max(value / target, 0), 1)
    }
}

struct NutritionWidgetSnapshot: Codable, Hashable {
    let dayKey: String
    let date: Date
    let eatenCalories: Double
    let calorieTarget: Double?
    let protein: Double
    let proteinTarget: Double?
    let carbs: Double
    let carbsTarget: Double?
    let fat: Double
    let fatTarget: Double?
    let activeBurnedCalories: Double?
    let restingBurnedCalories: Double?
    let goalSnapshots: [NutritionWidgetGoalSnapshot]
    let hasNutritionData: Bool
    let updatedAt: Date

    var calorieProgress: Double {
        guard let calorieTarget, calorieTarget > 0 else { return 0 }
        return min(max(eatenCalories / calorieTarget, 0), 1)
    }

    var totalBurnedCalories: Double? {
        guard let activeBurnedCalories, let restingBurnedCalories else { return nil }
        return activeBurnedCalories + restingBurnedCalories
    }

    var energyBalance: Double? {
        guard let totalBurnedCalories else { return nil }
        return eatenCalories - totalBurnedCalories
    }

    var hasBurnedData: Bool {
        totalBurnedCalories != nil
    }

    static var placeholder: NutritionWidgetSnapshot {
        NutritionWidgetSnapshot(
            dayKey: "preview",
            date: Date(),
            eatenCalories: 1680,
            calorieTarget: 2400,
            protein: 118,
            proteinTarget: 160,
            carbs: 185,
            carbsTarget: 260,
            fat: 54,
            fatTarget: 75,
            activeBurnedCalories: 560,
            restingBurnedCalories: 1720,
            goalSnapshots: [
                NutritionWidgetGoalSnapshot(key: "fiber", name: "Fiber", value: 21, target: 30, unit: "g")
            ],
            hasNutritionData: true,
            updatedAt: Date()
        )
    }

    static var empty: NutritionWidgetSnapshot {
        NutritionWidgetSnapshot(
            dayKey: "empty",
            date: Date(),
            eatenCalories: 0,
            calorieTarget: nil,
            protein: 0,
            proteinTarget: nil,
            carbs: 0,
            carbsTarget: nil,
            fat: 0,
            fatTarget: nil,
            activeBurnedCalories: nil,
            restingBurnedCalories: nil,
            goalSnapshots: [],
            hasNutritionData: false,
            updatedAt: Date()
        )
    }
}

enum NutritionWidgetSnapshotStore {
    static let widgetKind = "NutritionWidget"

    private static let appGroupIdentifier = "group.net.novapro.GymTracker"
    private static let snapshotKey = "nutrition.widget.snapshot.v1"

    static func load() -> NutritionWidgetSnapshot? {
        guard
            let defaults = UserDefaults(suiteName: appGroupIdentifier),
            let data = defaults.data(forKey: snapshotKey)
        else {
            return nil
        }
        return try? JSONDecoder().decode(NutritionWidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: NutritionWidgetSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    static func clear() {
        UserDefaults(suiteName: appGroupIdentifier)?.removeObject(forKey: snapshotKey)
    }
}
