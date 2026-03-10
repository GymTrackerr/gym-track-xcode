import Foundation
import SwiftData

@MainActor
enum LegacyStoreRecoveryService {
    static func recoverIfNeeded(destinationContext: ModelContext) {
        do {
            let destinationUserCount = try destinationContext.fetch(FetchDescriptor<User>()).count
            guard destinationUserCount == 0 else { return }

            let legacyContainer = try SharedModelConfig.createLegacyModelContainer()
            let legacyContext = legacyContainer.mainContext

            let legacyUsers = try legacyContext.fetch(FetchDescriptor<User>())
            guard !legacyUsers.isEmpty else { return }

            try migrateAllData(from: legacyContext, to: destinationContext)
            print("Legacy store recovery complete: imported \(legacyUsers.count) user account(s).")
        } catch {
            print("Legacy store recovery skipped: \(error)")
        }
    }

    private static func migrateAllData(from source: ModelContext, to destination: ModelContext) throws {
        let users = try source.fetch(FetchDescriptor<User>())
        let routines = try source.fetch(FetchDescriptor<Routine>())
        let exercises = try source.fetch(FetchDescriptor<Exercise>())
        let sessions = try source.fetch(FetchDescriptor<Session>())
        let exerciseSplits = try source.fetch(FetchDescriptor<ExerciseSplitDay>())
        let sessionEntries = try source.fetch(FetchDescriptor<SessionEntry>())
        let sessionSets = try source.fetch(FetchDescriptor<SessionSet>())
        let sessionReps = try source.fetch(FetchDescriptor<SessionRep>())
        let foods = try source.fetch(FetchDescriptor<Food>())
        let meals = try source.fetch(FetchDescriptor<Meal>())
        let mealEntries = try source.fetch(FetchDescriptor<MealEntry>())
        let foodLogs = try source.fetch(FetchDescriptor<FoodLog>())
        let mealItems = try source.fetch(FetchDescriptor<MealItem>())
        let nutritionTargets = try source.fetch(FetchDescriptor<NutritionTarget>())
        let trackerTimers = try source.fetch(FetchDescriptor<TrackerTimer>())

        var userById: [UUID: User] = [:]
        var routineById: [UUID: Routine] = [:]
        var exerciseById: [UUID: Exercise] = [:]
        var sessionById: [UUID: Session] = [:]
        var entryById: [UUID: SessionEntry] = [:]
        var setById: [UUID: SessionSet] = [:]
        var foodById: [UUID: Food] = [:]
        var mealById: [UUID: Meal] = [:]
        var mealEntryById: [UUID: MealEntry] = [:]

        for old in users {
            let copy = User(name: old.name)
            copy.id = old.id
            copy.timestamp = old.timestamp
            copy.lastLogin = old.lastLogin
            copy.active = old.active
            copy.allowHealthAccess = old.allowHealthAccess
            copy.defaultTimer = old.defaultTimer
            copy.showNutritionTab = old.showNutritionTab
            destination.insert(copy)
            userById[copy.id] = copy
        }

        for old in routines {
            let copy = Routine(order: old.order, name: old.name, user_id: old.user_id)
            copy.id = old.id
            copy.timestamp = old.timestamp
            copy.isArchived = old.isArchived
            copy.aliases = old.aliases
            destination.insert(copy)
            routineById[copy.id] = copy
        }

        for old in exercises {
            let type = ExerciseType.fromPersisted(rawValue: old.type)
            let copy = Exercise(name: old.name, type: type, user_id: old.user_id, isUserCreated: old.isUserCreated)
            copy.id = old.id
            copy.npId = old.npId
            copy.aliases = old.aliases
            copy.primary_muscles = old.primary_muscles
            copy.secondary_muscles = old.secondary_muscles
            copy.equipment = old.equipment
            copy.category = old.category
            copy.instructions = old.instructions
            copy.images = old.images
            copy.cachedMedia = old.cachedMedia
            copy.isArchived = old.isArchived
            copy.timestamp = old.timestamp
            destination.insert(copy)
            exerciseById[copy.id] = copy
        }

        for old in sessions {
            let linkedRoutine = old.routine.flatMap { routineById[$0.id] }
            let copy = Session(timestamp: old.timestamp, user_id: old.user_id, routine: linkedRoutine, notes: old.notes)
            copy.id = old.id
            copy.timestampDone = old.timestampDone
            copy.importHash = old.importHash
            destination.insert(copy)
            sessionById[copy.id] = copy
        }

        for old in exerciseSplits {
            guard let linkedRoutine = routineById[old.routine.id],
                  let linkedExercise = exerciseById[old.exercise.id] else { continue }
            let copy = ExerciseSplitDay(order: old.order, routine: linkedRoutine, exercise: linkedExercise)
            copy.id = old.id
            destination.insert(copy)
        }

        for old in sessionEntries {
            guard let linkedSession = sessionById[old.session.id],
                  let linkedExercise = exerciseById[old.exercise.id] else { continue }
            let copy = SessionEntry(order: old.order, session: linkedSession, exercise: linkedExercise)
            copy.id = old.id
            copy.isCompleted = old.isCompleted
            destination.insert(copy)
            entryById[copy.id] = copy
        }

        for old in sessionSets {
            guard let linkedEntry = entryById[old.sessionEntry.id] else { continue }
            let copy = SessionSet(order: old.order, sessionEntry: linkedEntry, notes: old.notes)
            copy.id = old.id
            copy.timestamp = old.timestamp
            copy.durationSeconds = old.durationSeconds
            copy.distance = old.distance
            copy.paceSeconds = old.paceSeconds
            copy.distanceUnitRaw = old.distanceUnitRaw
            copy.restSeconds = old.restSeconds
            copy.isCompleted = old.isCompleted
            copy.isDropSet = old.isDropSet
            destination.insert(copy)
            setById[copy.id] = copy
        }

        for old in sessionReps {
            guard let linkedSet = setById[old.sessionSet.id] else { continue }
            let unit = WeightUnit(rawValue: old.weight_unit) ?? .lb
            let copy = SessionRep(sessionSet: linkedSet, weight: old.weight, weight_unit: unit, count: old.count, notes: old.notes)
            copy.id = old.id
            copy.baseWeight = old.baseWeight
            copy.perSideWeight = old.perSideWeight
            copy.isPerSide = old.isPerSide
            destination.insert(copy)
        }

        for old in foods {
            let kind = FoodKind(rawValue: old.kindRaw) ?? .food
            let unit = FoodUnit(rawValue: old.unitRaw) ?? .grams
            let copy = Food(
                userId: old.userId,
                name: old.name,
                brand: old.brand,
                referenceLabel: old.referenceLabel,
                gramsPerReference: old.gramsPerReference,
                kcalPerReference: old.kcalPerReference,
                proteinPerReference: old.proteinPerReference,
                carbPerReference: old.carbPerReference,
                fatPerReference: old.fatPerReference,
                isArchived: old.isArchived,
                isFavorite: old.isFavorite,
                kind: kind,
                unit: unit
            )
            copy.id = old.id
            copy.createdAt = old.createdAt
            copy.updatedAt = old.updatedAt
            destination.insert(copy)
            foodById[copy.id] = copy
        }

        for old in meals {
            let category = FoodLogCategory(rawValue: old.defaultCategoryRaw) ?? .other
            let copy = Meal(userId: old.userId, name: old.name, defaultCategory: category)
            copy.id = old.id
            copy.createdAt = old.createdAt
            copy.updatedAt = old.updatedAt
            destination.insert(copy)
            mealById[copy.id] = copy
        }

        for old in mealEntries {
            let category = FoodLogCategory(rawValue: old.categoryRaw) ?? .other
            let linkedTemplateMeal = old.templateMeal.flatMap { mealById[$0.id] }
            let copy = MealEntry(
                userId: old.userId,
                timestamp: old.timestamp,
                category: category,
                note: old.note,
                templateMeal: linkedTemplateMeal
            )
            copy.id = old.id
            destination.insert(copy)
            mealEntryById[copy.id] = copy
        }

        for old in foodLogs {
            guard let linkedFood = foodById[old.food.id] else { continue }
            let category = FoodLogCategory(rawValue: old.categoryRaw) ?? .other
            let linkedMealEntry = old.mealEntry.flatMap { mealEntryById[$0.id] }
            let copy = FoodLog(
                userId: old.userId,
                timestamp: old.timestamp,
                category: category,
                grams: old.grams,
                note: old.note,
                quickCaloriesKcal: old.quickCaloriesKcal,
                food: linkedFood,
                mealEntry: linkedMealEntry
            )
            copy.id = old.id
            destination.insert(copy)
        }

        for old in mealItems {
            guard let linkedFood = foodById[old.food.id] else { continue }
            let linkedMeal = old.meal.flatMap { mealById[$0.id] }
            let copy = MealItem(order: old.order, grams: old.grams, meal: linkedMeal, food: linkedFood)
            copy.id = old.id
            destination.insert(copy)
        }

        for old in nutritionTargets {
            let copy = NutritionTarget(
                calorieTarget: old.calorieTarget,
                proteinTarget: old.proteinTarget,
                carbTarget: old.carbTarget,
                fatTarget: old.fatTarget,
                isEnabled: old.isEnabled
            )
            copy.id = old.id
            copy.createdAt = old.createdAt
            copy.updatedAt = old.updatedAt
            destination.insert(copy)
        }

        for old in trackerTimers {
            let copy = TrackerTimer(
                startTime: old.startTime,
                elapsedTime: old.elapsedTime,
                timerLength: old.timerLength,
                isPaused: old.isPaused
            )
            copy.id = old.id
            copy.createdAt = old.createdAt
            copy.updatedAt = old.updatedAt
            destination.insert(copy)
        }

        try destination.save()
    }
}
