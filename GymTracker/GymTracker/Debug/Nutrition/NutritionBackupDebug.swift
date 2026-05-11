#if DEBUG
import Foundation
import SwiftData

final class NutritionBackupDebug {
    private static var hasRun = false

    static func runSamples() {
        guard !hasRun else { return }
        hasRun = true

        print("=== NutritionBackupDebug start ===")
        let results = [
            testLegacyV2ImportBackfillsNewNutritionFields(),
            testExtraNutrientImportNormalizesKeys()
        ]
        let passCount = results.filter { $0 }.count
        print("=== NutritionBackupDebug done: \(passCount)/\(results.count) passed ===")
    }

    @discardableResult
    private static func testLegacyV2ImportBackfillsNewNutritionFields() -> Bool {
        do {
            let harness = try makeHarness()
            let user = User(name: "Nutrition Backup Legacy")
            harness.context.insert(user)
            try harness.context.save()

            let backupURL = try writeBackup("""
            {
              "schemaVersion": 2,
              "exportedAt": "2026-05-01T10:00:00Z",
              "userId": "\(user.id.uuidString)",
              "foodItems": [
                {
                  "id": "11111111-1111-1111-1111-111111111111",
                  "userId": "\(user.id.uuidString)",
                  "name": "Legacy Oats",
                  "brand": null,
                  "referenceLabel": "100 g",
                  "referenceQuantity": 100,
                  "caloriesPerReference": 389,
                  "proteinPerReference": 17,
                  "carbsPerReference": 66,
                  "fatPerReference": 7,
                  "isArchived": false,
                  "isFavorite": true,
                  "kindRaw": 0,
                  "unitRaw": 0,
                  "createdAt": "2026-05-01T10:00:00Z",
                  "updatedAt": "2026-05-01T10:00:00Z"
                }
              ],
              "mealRecipes": [],
              "mealRecipeItems": [],
              "nutritionLogEntries": [
                {
                  "id": "22222222-2222-2222-2222-222222222222",
                  "userId": "\(user.id.uuidString)",
                  "timestamp": "2026-05-01T10:05:00Z",
                  "logTypeRaw": 2,
                  "sourceItemId": null,
                  "sourceMealId": null,
                  "amount": 1,
                  "amountUnitSnapshot": "entry",
                  "categoryRaw": 4,
                  "note": null,
                  "dayKey": "2026-05-01",
                  "logDate": "2026-05-01T00:00:00Z",
                  "creationMethodRaw": 3,
                  "nameSnapshot": "Quick Add",
                  "brandSnapshot": null,
                  "servingUnitLabelSnapshot": null,
                  "caloriesSnapshot": 250,
                  "proteinSnapshot": 0,
                  "carbsSnapshot": 0,
                  "fatSnapshot": 0,
                  "createdAt": "2026-05-01T10:05:00Z",
                  "updatedAt": "2026-05-01T10:05:00Z"
                }
              ],
              "nutritionTargets": [
                {
                  "id": "33333333-3333-3333-3333-333333333333",
                  "createdAt": "2026-05-01T10:00:00Z",
                  "updatedAt": "2026-05-01T10:00:00Z",
                  "calorieTarget": 2500,
                  "proteinTarget": 180,
                  "carbTarget": 250,
                  "fatTarget": 80,
                  "isEnabled": true
                }
              ]
            }
            """)

            let service = NutritionBackupService(context: harness.context, currentUserProvider: { user })
            let result = try service.importNutritionJSON(from: backupURL)
            let foods = try harness.context.fetch(FetchDescriptor<FoodItem>())
            let logs = try harness.context.fetch(FetchDescriptor<NutritionLogEntry>())
            let targets = try harness.context.fetch(FetchDescriptor<NutritionTarget>())
            let definitions = try harness.context.fetch(FetchDescriptor<NutritionNutrientDefinition>())

            var ok = true
            ok = ok && check("nutrition-backup-test1", result.nutrientDefinitions > 0, "Expected bundled definitions to seed for old backups")
            ok = ok && check("nutrition-backup-test1", !definitions.isEmpty, "Expected nutrient definitions after import")
            ok = ok && check("nutrition-backup-test1", foods.first?.servingUnitLabel == "100 g", "Expected reference label to backfill serving label")
            ok = ok && check("nutrition-backup-test1", foods.first?.servingQuantity == 100, "Expected reference amount to backfill serving quantity")
            ok = ok && check("nutrition-backup-test1", foods.first?.hasProvidedNutrient(NutritionNutrientKey.calories) == true, "Expected core food nutrients to remain provided")
            ok = ok && check("nutrition-backup-test1", logs.first?.hasProvidedNutrient(NutritionNutrientKey.calories) == true, "Expected legacy quick log calories to remain provided")
            ok = ok && check("nutrition-backup-test1", targets.first?.labelProfile == .defaultProfile, "Expected missing label profile to default")

            print("[nutrition-backup-test1] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("nutrition-backup-test1", "Unexpected error: \(error)")
        }
    }

    @discardableResult
    private static func testExtraNutrientImportNormalizesKeys() -> Bool {
        do {
            let harness = try makeHarness()
            let user = User(name: "Nutrition Backup Extras")
            harness.context.insert(user)
            try harness.context.save()

            let backupURL = try writeBackup("""
            {
              "schemaVersion": 2,
              "exportedAt": "2026-05-01T10:00:00Z",
              "userId": "\(user.id.uuidString)",
              "foodItems": [
                {
                  "id": "44444444-4444-4444-4444-444444444444",
                  "userId": "\(user.id.uuidString)",
                  "name": "Fiber Bar",
                  "brand": null,
                  "referenceLabel": null,
                  "referenceQuantity": 60,
                  "servingQuantity": 60,
                  "servingUnitLabel": "bar",
                  "labelProfile": "hybrid",
                  "caloriesPerReference": 210,
                  "proteinPerReference": 20,
                  "carbsPerReference": 24,
                  "fatPerReference": 6,
                  "extraNutrients": { "Dietary Fiber": 9 },
                  "isArchived": false,
                  "isFavorite": false,
                  "kindRaw": 0,
                  "unitRaw": 0,
                  "createdAt": "2026-05-01T10:00:00Z",
                  "updatedAt": "2026-05-01T10:00:00Z"
                }
              ],
              "mealRecipes": [],
              "mealRecipeItems": [],
              "nutritionLogEntries": [
                {
                  "id": "55555555-5555-5555-5555-555555555555",
                  "userId": "\(user.id.uuidString)",
                  "timestamp": "2026-05-01T10:05:00Z",
                  "logTypeRaw": 2,
                  "sourceItemId": null,
                  "sourceMealId": null,
                  "amount": 1,
                  "amountUnitSnapshot": "entry",
                  "categoryRaw": 4,
                  "note": null,
                  "dayKey": "2026-05-01",
                  "logDate": "2026-05-01T00:00:00Z",
                  "creationMethodRaw": 3,
                  "nameSnapshot": "Protein Fiber Quick Add",
                  "brandSnapshot": null,
                  "servingUnitLabelSnapshot": null,
                  "amountMode": 2,
                  "caloriesSnapshot": 0,
                  "proteinSnapshot": 25,
                  "carbsSnapshot": 0,
                  "fatSnapshot": 0,
                  "extraNutrientsSnapshot": { "Fiber": 8 },
                  "createdAt": "2026-05-01T10:05:00Z",
                  "updatedAt": "2026-05-01T10:05:00Z"
                }
              ],
              "nutritionTargets": []
            }
            """)

            let service = NutritionBackupService(context: harness.context, currentUserProvider: { user })
            _ = try service.importNutritionJSON(from: backupURL)
            let foods = try harness.context.fetch(FetchDescriptor<FoodItem>())
            let logs = try harness.context.fetch(FetchDescriptor<NutritionLogEntry>())

            let food = foods.first
            let log = logs.first
            var ok = true
            ok = ok && check("nutrition-backup-test2", food?.extraNutrients?["dietary-fiber"] == 9, "Expected food extra nutrient key normalization")
            ok = ok && check("nutrition-backup-test2", food?.hasProvidedNutrient("dietary-fiber") == true, "Expected imported food provided keys to include extras")
            ok = ok && check("nutrition-backup-test2", food?.labelProfile == .defaultProfile, "Expected legacy hybrid profile to decode as default")
            ok = ok && check("nutrition-backup-test2", log?.extraNutrientsSnapshot?["fiber"] == 8, "Expected log extra nutrient key normalization")
            ok = ok && check("nutrition-backup-test2", log?.hasProvidedNutrient(NutritionNutrientKey.protein) == true, "Expected quick log protein to be inferred as provided")
            ok = ok && check("nutrition-backup-test2", log?.hasProvidedNutrient("fiber") == true, "Expected quick log extra nutrient to be provided")
            ok = ok && check("nutrition-backup-test2", log?.hasProvidedNutrient(NutritionNutrientKey.calories) == false, "Expected zero-calorie protein quick log not to infer calories")

            print("[nutrition-backup-test2] \(ok ? "PASS" : "FAIL")")
            return ok
        } catch {
            return fail("nutrition-backup-test2", "Unexpected error: \(error)")
        }
    }

    private static func makeHarness() throws -> Harness {
        let schema = Schema([
            User.self,
            SyncMetadataItem.self,
            NutritionTarget.self,
            NutritionNutrientDefinition.self,
            FoodItem.self,
            MealRecipe.self,
            MealRecipeItem.self,
            NutritionLogEntry.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        return Harness(container: container, context: context)
    }

    private static func writeBackup(_ json: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nutrition-backup-debug-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url, options: .atomic)
        return url
    }

    @discardableResult
    private static func check(_ test: String, _ condition: Bool, _ message: String) -> Bool {
        if !condition {
            print("[\(test)] FAIL: \(message)")
        }
        return condition
    }

    @discardableResult
    private static func fail(_ test: String, _ message: String) -> Bool {
        print("[\(test)] FAIL: \(message)")
        return false
    }

    private struct Harness {
        let container: ModelContainer
        let context: ModelContext
    }
}
#endif
