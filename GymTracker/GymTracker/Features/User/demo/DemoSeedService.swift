import Foundation
import SwiftData

@MainActor
final class DemoSeedService {
    private let modelContext: ModelContext
    private let userService: UserService
    private let calendar = Calendar.current

    private let defaultDemoUserName = "Demo"
    private let lastRealUserDefaultsKey = "demo.lastRealUserId"

    init(context: ModelContext, userService: UserService) {
        self.modelContext = context
        self.userService = userService
    }

    func isDemoUser(_ user: User?) -> Bool {
        user?.isDemo == true
    }

    func ensureDemoUser(named preferredName: String? = nil) throws -> User {
        let resolvedName = resolvedDemoName(preferredName)
        if let existing = try allUsers().first(where: \.isDemo) {
            existing.name = resolvedName
            existing.allowHealthAccess = true
            existing.showNutritionTab = true
            try modelContext.save()
            return existing
        }

        let demoUser = User(name: resolvedName, isDemo: true)
        demoUser.allowHealthAccess = true
        demoUser.showNutritionTab = true
        modelContext.insert(demoUser)
        try modelContext.save()
        userService.loadAccounts()
        return demoUser
    }

    func sourceUserSummary() throws -> String {
        if let user = try sourceUser() {
            return "\(user.name) (\(demoExerciseCount(for: user)) exercises)"
        }
        return "No source account available"
    }

    func enterDemoMode(configuration: DemoSeedConfiguration) throws -> DemoSeedSummary {
        if let current = userService.currentUser, !current.isDemo {
            rememberRealUser(current.id)
        }

        let demoUser = try ensureDemoUser(named: configuration.demoUserName)
        let summary: DemoSeedSummary
        if try hasSeededData(for: demoUser) {
            try saveConfigurationProfile(configuration)
            summary = try summarizeDemoData(for: demoUser)
        } else {
            summary = try resetDemoData(configuration: configuration)
        }

        userService.loadAccounts()
        userService.switchAccount(to: demoUser.id)
        return summary
    }

    func resetDemoData(configuration: DemoSeedConfiguration) throws -> DemoSeedSummary {
        if let current = userService.currentUser, !current.isDemo {
            rememberRealUser(current.id)
        }

        let presets = try DemoTemplateLoader.loadPresets()
        let routines = try DemoTemplateLoader.loadRoutines()
        let nutrition = try DemoTemplateLoader.loadNutrition()
        let demoUser = try ensureDemoUser(named: configuration.demoUserName)
        guard let sourceUser = try sourceUser() else {
            throw DemoSeedError.missingSourceUser
        }

        try purgeDemoData(for: demoUser)
        let clonedExercises = try cloneExercises(from: sourceUser, to: demoUser)
        guard !clonedExercises.isEmpty else {
            throw DemoSeedError.missingSourceExercises
        }

        let seededRoutines = try seedRoutines(
            from: routines.routines,
            exercises: clonedExercises,
            demoUser: demoUser,
            matching: presets.exerciseMatching
        )
        let sessionCount = try seedSessions(
            using: seededRoutines,
            configuration: configuration,
            noise: configuration.noise
        )
        let nutritionCounts = try seedNutrition(
            template: nutrition,
            demoUser: demoUser,
            configuration: configuration
        )
        let healthDayCount = try seedHealth(
            for: demoUser,
            configuration: configuration,
            presets: presets
        )

        demoUser.allowHealthAccess = true
        demoUser.showNutritionTab = true
        try saveConfigurationProfile(configuration)
        try modelContext.save()

        userService.loadAccounts()
        userService.switchAccount(to: demoUser.id)

        return DemoSeedSummary(
            exerciseCount: clonedExercises.count,
            routineCount: seededRoutines.count,
            sessionCount: sessionCount,
            mealCount: nutritionCounts.mealCount,
            logCount: nutritionCounts.logCount,
            healthDayCount: healthDayCount
        )
    }

    func exitDemoMode() throws {
        let allUsers = try self.allUsers()
        let fallbackUser = preferredRealUser(from: allUsers)
        guard let target = fallbackUser else {
            throw DemoSeedError.missingSourceUser
        }

        userService.loadAccounts()
        userService.switchAccount(to: target.id)
    }

    func savedProfiles() throws -> [DemoSeedProfile] {
        try DemoSeedProfileStore.savedProfiles(in: modelContext)
    }

    func lastUsedProfile() throws -> DemoSeedProfile? {
        try DemoSeedProfileStore.lastRanProfile(in: modelContext)
    }

    func configuration(for profile: DemoSeedProfile, presets: DemoPresetsBundle) -> DemoSeedConfiguration {
        DemoSeedConfiguration(profile: profile, presets: presets)
    }

    private func rememberRealUser(_ userId: UUID) {
        UserDefaults.standard.set(userId.uuidString, forKey: lastRealUserDefaultsKey)
    }

    private func saveConfigurationProfile(_ configuration: DemoSeedConfiguration) throws {
        let now = Date()
        for profile in try DemoSeedProfileStore.savedProfiles(in: modelContext) where profile.lastRan {
            profile.lastRan = false
            profile.updatedAt = now
        }

        let profile = DemoSeedProfile(configuration: configuration, lastRan: true, createdAt: now)
        modelContext.insert(profile)
        try modelContext.save()
    }

    private func resolvedDemoName(_ preferredName: String?) -> String {
        let trimmed = preferredName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultDemoUserName : trimmed
    }

    private func sourceUser() throws -> User? {
        let users = try allUsers().filter { !$0.isDemo }
        if let current = userService.currentUser, !current.isDemo {
            return current
        }
        return preferredRealUser(from: users)
    }

    private func preferredRealUser(from users: [User]) -> User? {
        guard !users.isEmpty else { return nil }

        if let raw = UserDefaults.standard.string(forKey: lastRealUserDefaultsKey),
           let lastRealId = UUID(uuidString: raw),
           let match = users.first(where: { $0.id == lastRealId }) {
            return match
        }

        return users.sorted { $0.lastLogin > $1.lastLogin }.first
    }

    private func hasSeededData(for demoUser: User) throws -> Bool {
        let sessions = try modelContext.fetch(FetchDescriptor<Session>())
        return sessions.contains(where: { $0.user_id == demoUser.id })
    }

    private func summarizeDemoData(for demoUser: User) throws -> DemoSeedSummary {
        let exercises = try modelContext.fetch(FetchDescriptor<Exercise>()).filter { $0.user_id == demoUser.id }
        let routines = try modelContext.fetch(FetchDescriptor<Routine>()).filter { $0.user_id == demoUser.id && !$0.isArchived }
        let sessions = try modelContext.fetch(FetchDescriptor<Session>()).filter { $0.user_id == demoUser.id }
        let meals = try modelContext.fetch(FetchDescriptor<MealRecipe>()).filter { $0.userId == demoUser.id }
        let logs = try modelContext.fetch(FetchDescriptor<NutritionLogEntry>()).filter { $0.userId == demoUser.id }
        let health = try modelContext.fetch(FetchDescriptor<HealthKitDailyAggregateData>()).filter { $0.userId == demoUser.id.uuidString }

        return DemoSeedSummary(
            exerciseCount: exercises.count,
            routineCount: routines.count,
            sessionCount: sessions.count,
            mealCount: meals.count,
            logCount: logs.count,
            healthDayCount: health.count
        )
    }

    private func purgeDemoData(for demoUser: User) throws {
        for session in try modelContext.fetch(FetchDescriptor<Session>()).filter({ $0.user_id == demoUser.id }) {
            modelContext.delete(session)
        }

        for routine in try modelContext.fetch(FetchDescriptor<Routine>()).filter({ $0.user_id == demoUser.id }) {
            modelContext.delete(routine)
        }

        for exercise in try modelContext.fetch(FetchDescriptor<Exercise>()).filter({ $0.user_id == demoUser.id }) {
            modelContext.delete(exercise)
        }

        for item in try modelContext.fetch(FetchDescriptor<FoodItem>()).filter({ $0.userId == demoUser.id }) {
            modelContext.delete(item)
        }

        for meal in try modelContext.fetch(FetchDescriptor<MealRecipe>()).filter({ $0.userId == demoUser.id }) {
            modelContext.delete(meal)
        }

        for log in try modelContext.fetch(FetchDescriptor<NutritionLogEntry>()).filter({ $0.userId == demoUser.id }) {
            modelContext.delete(log)
        }

        for target in try modelContext.fetch(FetchDescriptor<NutritionTarget>()).filter({ $0.userId == demoUser.id }) {
            modelContext.delete(target)
        }

        for aggregate in try modelContext.fetch(FetchDescriptor<HealthKitDailyAggregateData>()).filter({ $0.userId == demoUser.id.uuidString }) {
            modelContext.delete(aggregate)
        }

        try modelContext.save()
    }

    private func cloneExercises(from sourceUser: User, to demoUser: User) throws -> [Exercise] {
        let sourceExercises = try modelContext.fetch(FetchDescriptor<Exercise>())
            .filter { $0.user_id == sourceUser.id }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        guard !sourceExercises.isEmpty else {
            throw DemoSeedError.missingSourceExercises
        }

        var cloned: [Exercise] = []
        for source in sourceExercises {
            let exercise = Exercise(
                name: source.name,
                type: source.exerciseType,
                user_id: demoUser.id,
                isUserCreated: source.isUserCreated
            )
            exercise.npId = source.npId
            exercise.aliases = source.aliases
            exercise.primary_muscles = source.primary_muscles
            exercise.secondary_muscles = source.secondary_muscles
            exercise.equipment = source.equipment
            exercise.category = source.category
            exercise.instructions = source.instructions
            exercise.images = source.images
            exercise.cachedMedia = source.cachedMedia
            exercise.isArchived = source.isArchived
            modelContext.insert(exercise)
            cloned.append(exercise)
        }

        try modelContext.save()
        return cloned
    }

    private func seedRoutines(
        from templates: [DemoRoutineTemplate],
        exercises: [Exercise],
        demoUser: User,
        matching: DemoExerciseMatchingPreset
    ) throws -> [Routine] {
        var routines: [Routine] = []
        let activeExercises = exercises.filter { !$0.isArchived }

        for (index, template) in templates.enumerated() {
            let routine = Routine(order: index, name: template.name, user_id: demoUser.id)
            modelContext.insert(routine)

            var usedExerciseIds = Set<UUID>()
            for (slotIndex, slot) in template.slots.enumerated() {
                guard let exercise = selectExercise(
                    for: slot,
                    from: activeExercises,
                    excluding: usedExerciseIds,
                    matching: matching
                ) else { continue }
                usedExerciseIds.insert(exercise.id)
                let split = ExerciseSplitDay(order: slotIndex, routine: routine, exercise: exercise)
                routine.exerciseSplits.append(split)
                modelContext.insert(split)
            }

            if !routine.exerciseSplits.isEmpty {
                routines.append(routine)
            } else {
                modelContext.delete(routine)
            }
        }

        try modelContext.save()
        return routines
    }

    private func selectExercise(
        for slot: DemoRoutineSlotTemplate,
        from exercises: [Exercise],
        excluding usedExerciseIds: Set<UUID>,
        matching: DemoExerciseMatchingPreset
    ) -> Exercise? {
        let available = exercises.filter { !usedExerciseIds.contains($0.id) }

        if matching.preferNpIdMatches,
           let preferredNpIds = slot.preferredNpIds?.map({ $0.lowercased() }),
           let npIdMatch = available.first(where: { exercise in
               guard let npId = exercise.npId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                     !npId.isEmpty else { return false }
               return preferredNpIds.contains(npId)
           }) {
            return npIdMatch
        }

        if matching.allowKeywordFallback {
            let matches = available.filter { exercise in
                let haystack = ([exercise.name] + (exercise.aliases ?? []) + (exercise.primary_muscles ?? []) + (exercise.secondary_muscles ?? []) + [exercise.category ?? "", exercise.equipment ?? ""])
                    .joined(separator: " ")
                    .lowercased()
                return slot.keywords.contains(where: { haystack.contains($0.lowercased()) })
            }
            if let first = matches.first {
                return first
            }
        }

        if matching.allowTypeFallback,
           let fallback = available.first(where: { exercise in
               let typeLabel = String(describing: exercise.exerciseType).lowercased()
               let category = (exercise.category ?? "").lowercased()
               return slot.fallbackTypes.contains(where: { typeLabel.contains($0.lowercased()) || category.contains($0.lowercased()) })
           }) {
            return fallback
        }

        return available.first
    }

    private func seedSessions(
        using routines: [Routine],
        configuration: DemoSeedConfiguration,
        noise: DemoNoisePreset
    ) throws -> Int {
        guard !routines.isEmpty else { return 0 }

        let dayStarts = dateSeries(days: configuration.sessionRange.days)
        var routineIndex = 0
        var perExerciseSessionCount: [UUID: Int] = [:]
        var sessionCount = 0

        for (index, dayStart) in dayStarts.enumerated() {
            let shouldCreate = shouldCreateSession(dayIndex: index, noise: noise)
            guard shouldCreate else { continue }

            let routine = routines[routineIndex % routines.count]
            routineIndex += 1

            let sessionDate = dayStart.addingTimeInterval(TimeInterval(18 * 3600 + (index % 3) * 900))
            let note = routineTemplateNote(for: routine.name, dayIndex: index)
            let session = Session(timestamp: sessionDate, user_id: routine.user_id, routine: routine, notes: note)
            session.timestampDone = sessionDate.addingTimeInterval(TimeInterval(60 * (55 + (index % 4) * 10)))
            modelContext.insert(session)

            for split in routine.exerciseSplits.sorted(by: { $0.order < $1.order }) {
                let entry = SessionEntry(order: split.order, session: session, exercise: split.exercise)
                entry.isCompleted = true
                session.sessionEntries.append(entry)
                modelContext.insert(entry)

                let template = slotTemplate(for: split.exercise, in: routine.name)
                let previousCount = perExerciseSessionCount[split.exercise.id, default: 0]
                perExerciseSessionCount[split.exercise.id] = previousCount + 1
                seedSets(
                    for: entry,
                    exercise: split.exercise,
                    slotTemplate: template,
                    progressionIndex: previousCount,
                    dayIndex: index,
                    noise: noise
                )
            }

            sessionCount += 1
        }

        try modelContext.save()
        return sessionCount
    }

    private func slotTemplate(for exercise: Exercise, in routineName: String) -> DemoRoutineSlotTemplate? {
        guard let bundle = try? DemoTemplateLoader.loadRoutines() else { return nil }
        guard let routine = bundle.routines.first(where: { $0.name == routineName }) else { return nil }
        return routine.slots.first { slot in
            let haystack = exercise.name.lowercased()
            return slot.keywords.contains(where: { haystack.contains($0.lowercased()) })
        }
    }

    private func seedSets(
        for entry: SessionEntry,
        exercise: Exercise,
        slotTemplate: DemoRoutineSlotTemplate?,
        progressionIndex: Int,
        dayIndex: Int,
        noise: DemoNoisePreset
    ) {
        let isCardio = exercise.exerciseType == .cardio || slotTemplate?.style.lowercased() == "cardio"
        let setCount = max(1, slotTemplate?.sets ?? (isCardio ? 1 : 3))

        for setIndex in 0..<setCount {
            let set = SessionSet(order: setIndex, sessionEntry: entry)
            set.isCompleted = true
            entry.sets.append(set)
            modelContext.insert(set)

            if isCardio {
                let durationRange = slotTemplate?.durationMinutesRange ?? [18, 35]
                let distanceRange = slotTemplate?.distanceRange ?? [2.5, 5.5]
                let durationMinutes = interpolatedValue(
                    dayIndex: dayIndex + setIndex,
                    minValue: Double(durationRange.first ?? 18),
                    maxValue: Double(durationRange.last ?? 35),
                    amplitude: noise.sessionScale
                )
                let distance = interpolatedValue(
                    dayIndex: dayIndex + setIndex + 7,
                    minValue: distanceRange.first ?? 2.5,
                    maxValue: distanceRange.last ?? 5.5,
                    amplitude: noise.sessionScale
                )
                set.durationSeconds = Int(durationMinutes.rounded()) * 60
                set.distance = (distance * 10).rounded() / 10
                set.distanceUnit = DistanceUnit(rawValue: slotTemplate?.distanceUnit ?? "km") ?? .km
                if let durationSeconds = set.durationSeconds, let distance = set.distance, distance > 0 {
                    set.paceSeconds = Int((Double(durationSeconds) / distance).rounded())
                }
                continue
            }

            let repRange = slotTemplate?.repRange ?? [6, 12]
            let minReps = repRange.first ?? 6
            let maxReps = repRange.last ?? max(minReps, 10)
            let reps = Int(interpolatedValue(dayIndex: dayIndex + setIndex, minValue: Double(minReps), maxValue: Double(maxReps), amplitude: noise.sessionScale).rounded())

            let baseWeight = resolvedBaseWeight(for: exercise, slotTemplate: slotTemplate)
            let increment = (slotTemplate?.weightStep ?? inferredWeightStep(for: exercise)) * Double(progressionIndex)
            let fatigueAdjustment = Double(setIndex) * (0.8 + 0.3 * noise.sessionScale)
            let weight = max(
                5,
                baseWeight + increment - fatigueAdjustment + signedNoise(dayIndex: dayIndex + setIndex, salt: progressionIndex + 3) * 2.0 * noise.sessionScale
            )

            let rep = SessionRep(
                sessionSet: set,
                weight: (weight * 2).rounded() / 2,
                weight_unit: .lb,
                count: max(1, reps)
            )
            set.sessionReps.append(rep)
            modelContext.insert(rep)
        }
    }

    private func resolvedBaseWeight(for exercise: Exercise, slotTemplate: DemoRoutineSlotTemplate?) -> Double {
        if let weightBase = slotTemplate?.weightBase {
            return weightBase
        }

        let name = exercise.name.lowercased()
        if name.contains("deadlift") {
            return 205
        }
        if name.contains("squat") || name.contains("leg press") {
            return 185
        }
        if name.contains("bench") || name.contains("press") {
            return 115
        }
        if name.contains("row") || name.contains("pull") {
            return 95
        }
        if name.contains("curl") || name.contains("raise") {
            return 30
        }
        return 65
    }

    private func inferredWeightStep(for exercise: Exercise) -> Double {
        let name = exercise.name.lowercased()
        if name.contains("deadlift") || name.contains("squat") {
            return 5
        }
        if name.contains("bench") || name.contains("press") || name.contains("row") {
            return 2.5
        }
        return 1
    }

    private func seedNutrition(
        template: DemoNutritionTemplateBundle,
        demoUser: User,
        configuration: DemoSeedConfiguration
    ) throws -> (mealCount: Int, logCount: Int) {
        var foodsByTemplateId: [String: FoodItem] = [:]

        for foodTemplate in template.foods {
            let item = FoodItem(
                userId: demoUser.id,
                name: foodTemplate.name,
                brand: foodTemplate.brand,
                referenceLabel: foodTemplate.referenceLabel,
                referenceQuantity: foodTemplate.referenceQuantity,
                caloriesPerReference: foodTemplate.calories,
                proteinPerReference: foodTemplate.protein,
                carbsPerReference: foodTemplate.carbs,
                fatPerReference: foodTemplate.fat,
                extraNutrients: nil,
                isArchived: false,
                isFavorite: foodTemplate.favorite ?? false,
                kind: .demoValue(from: foodTemplate.kind),
                unit: .demoValue(from: foodTemplate.unit)
            )
            modelContext.insert(item)
            foodsByTemplateId[foodTemplate.id] = item
        }

        var mealsByTemplateId: [String: MealRecipe] = [:]
        for mealTemplate in template.meals {
            let meal = MealRecipe(
                userId: demoUser.id,
                name: mealTemplate.name,
                batchSize: mealTemplate.batchSize,
                servingUnitLabel: mealTemplate.servingUnitLabel,
                defaultCategory: .demoValue(from: mealTemplate.defaultCategory),
                cachedExtraNutrients: nil,
                isArchived: false
            )
            modelContext.insert(meal)

            for (itemIndex, itemTemplate) in mealTemplate.items.enumerated() {
                guard let food = foodsByTemplateId[itemTemplate.foodId] else { continue }
                let recipeItem = MealRecipeItem(
                    amount: itemTemplate.amount,
                    amountUnit: food.unit,
                    order: itemIndex,
                    mealRecipe: meal,
                    foodItem: food
                )
                meal.items.append(recipeItem)
                modelContext.insert(recipeItem)
            }

            mealsByTemplateId[mealTemplate.id] = meal
        }

        let target = NutritionTarget(
            userId: demoUser.id,
            calorieTarget: configuration.healthTargets.nutritionCalories.mean,
            proteinTarget: template.target.protein,
            carbTarget: template.target.carbs,
            fatTarget: template.target.fat,
            isEnabled: true
        )
        modelContext.insert(target)

        let dayStarts = dateSeries(days: configuration.nutritionRange.days)
        var logCount = 0
        let snackMealIds = (template.patterns.weekday + template.patterns.weekend)
            .filter { FoodLogCategory.demoValue(from: $0.category) == .snack }
            .flatMap(\.mealIds)
        for (dayIndex, dayStart) in dayStarts.enumerated() {
            let patterns = calendar.isDateInWeekend(dayStart) ? template.patterns.weekend : template.patterns.weekday
            var dayLogs: [NutritionLogEntry] = []
            for (slotIndex, slot) in patterns.enumerated() {
                guard probabilityHit(slot.probability, dayIndex: dayIndex + slotIndex * 11, scale: configuration.noise.nutritionScale) else { continue }
                guard let mealId = pickValue(slot.mealIds, dayIndex: dayIndex + slotIndex),
                      let meal = mealsByTemplateId[mealId] else { continue }

                let amount = interpolatedValue(
                    dayIndex: dayIndex + slotIndex,
                    minValue: slot.amountRange.first ?? 0.9,
                    maxValue: slot.amountRange.last ?? 1.1,
                    amplitude: configuration.noise.nutritionScale
                )
                let timestamp = dayStart.addingTimeInterval(TimeInterval((7 + slotIndex * 4) * 3600 + (dayIndex % 3) * 600))
                let note = pickValue(slot.noteOptions ?? [], dayIndex: dayIndex + slotIndex * 3)
                let log = nutritionLogEntry(
                    meal: meal,
                    amount: amount,
                    timestamp: timestamp,
                    category: .demoValue(from: slot.category),
                    note: note
                )
                dayLogs.append(log)
            }

            let lowTarget = max(0, configuration.healthTargets.nutritionCalories.mean - configuration.healthTargets.nutritionCalories.range)
            var totalCalories = dayLogs.reduce(0) { $0 + $1.caloriesSnapshot }
            var addedSnackCount = 0
            while totalCalories < lowTarget && addedSnackCount < 3 {
                guard let mealId = pickValue(snackMealIds, dayIndex: dayIndex + addedSnackCount),
                      let snackMeal = mealsByTemplateId[mealId] else { break }

                let snackAmount = interpolatedValue(
                    dayIndex: dayIndex + addedSnackCount + 100,
                    minValue: 0.85,
                    maxValue: 1.15,
                    amplitude: configuration.noise.nutritionScale
                )
                let snackTimestamp = dayStart.addingTimeInterval(TimeInterval((15 + addedSnackCount * 2) * 3600))
                let snackLog = nutritionLogEntry(
                    meal: snackMeal,
                    amount: snackAmount,
                    timestamp: snackTimestamp,
                    category: .snack,
                    note: "Added to hit calorie target."
                )
                dayLogs.append(snackLog)
                totalCalories += snackLog.caloriesSnapshot
                addedSnackCount += 1
            }

            for log in dayLogs {
                modelContext.insert(log)
                logCount += 1
            }
        }

        try modelContext.save()
        return (mealCount: mealsByTemplateId.count, logCount: logCount)
    }

    private func nutritionLogEntry(
        meal: MealRecipe,
        amount: Double,
        timestamp: Date,
        category: FoodLogCategory,
        note: String?
    ) -> NutritionLogEntry {
        let nutrition = recipeNutrition(meal: meal, amount: amount)
        return NutritionLogEntry(
            userId: meal.userId,
            timestamp: timestamp,
            logType: .meal,
            sourceItemId: nil,
            sourceMealId: meal.id,
            amount: amount,
            amountUnitSnapshot: "serving",
            category: category,
            note: note,
            dayKey: dayKey(for: timestamp),
            logDate: calendar.startOfDay(for: timestamp),
            creationMethod: .mealRecipe,
            nameSnapshot: meal.name,
            brandSnapshot: nil,
            servingUnitLabelSnapshot: meal.servingUnitLabel,
            caloriesSnapshot: nutrition.calories,
            proteinSnapshot: nutrition.protein,
            carbsSnapshot: nutrition.carbs,
            fatSnapshot: nutrition.fat,
            extraNutrientsSnapshot: nil,
            recipeItemsSnapshot: nutrition.recipeItems
        )
    }

    private func recipeNutrition(meal: MealRecipe, amount: Double) -> (calories: Double, protein: Double, carbs: Double, fat: Double, recipeItems: [RecipeItemSnapshot]) {
        let servingMultiplier = amount / max(meal.batchSize, 0.0001)
        var calories = 0.0
        var protein = 0.0
        var carbs = 0.0
        var fat = 0.0
        var snapshots: [RecipeItemSnapshot] = []

        for item in meal.items.sorted(by: { $0.order < $1.order }) {
            let food = item.foodItem
            let factor = item.amount / max(food.referenceQuantity, 0.0001) * servingMultiplier
            let itemCalories = food.caloriesPerReference * factor
            let itemProtein = food.proteinPerReference * factor
            let itemCarbs = food.carbsPerReference * factor
            let itemFat = food.fatPerReference * factor
            calories += itemCalories
            protein += itemProtein
            carbs += itemCarbs
            fat += itemFat
            snapshots.append(
                RecipeItemSnapshot(
                    name: food.name,
                    amount: item.amount * servingMultiplier,
                    amountUnit: food.unit.shortLabel,
                    caloriesSnapshot: itemCalories,
                    proteinSnapshot: itemProtein,
                    carbsSnapshot: itemCarbs,
                    fatSnapshot: itemFat,
                    extraNutrientsSnapshot: nil
                )
            )
        }

        return (calories, protein, carbs, fat, snapshots)
    }

    private func seedHealth(
        for demoUser: User,
        configuration: DemoSeedConfiguration,
        presets: DemoPresetsBundle
    ) throws -> Int {
        let dayStarts = dateSeries(days: configuration.healthRange.days)

        for (index, dayStart) in dayStarts.enumerated() {
            let steps = metricValue(
                setting: configuration.healthTargets.steps,
                dayIndex: index,
                scale: configuration.noise.healthScale,
                weeklyAmplitude: 0.45
            )
            let active = metricValue(
                setting: configuration.healthTargets.activeEnergyKcal,
                dayIndex: index + 13,
                scale: configuration.noise.healthScale,
                weeklyAmplitude: 0.35,
                correlation: (steps - configuration.healthTargets.steps.mean) / max(configuration.healthTargets.steps.mean, 1) * 90
            )
            let resting = metricValue(
                setting: configuration.healthTargets.restingEnergyKcal,
                dayIndex: index + 23,
                scale: configuration.noise.healthScale * 0.5,
                weeklyAmplitude: 0.12
            )
            let sleepHours = metricValue(
                setting: configuration.healthTargets.sleepHours,
                dayIndex: index + 31,
                scale: configuration.noise.healthScale,
                weeklyAmplitude: 0.25
            )
            let weightKg = metricValue(
                setting: configuration.healthTargets.bodyWeightKg,
                dayIndex: index + 41,
                scale: configuration.noise.healthScale * 0.45,
                weeklyAmplitude: 0.08
            )
            let exerciseMinutes = metricValue(
                setting: configuration.healthTargets.exerciseMinutes,
                dayIndex: index + 17,
                scale: configuration.noise.healthScale,
                weeklyAmplitude: 0.3
            )
            let standHours = max(1, min(12, Int((steps / 900).rounded())))
            let moveGoal = max(configuration.healthTargets.activeEnergyKcal.mean, 400)
            let exerciseGoal = max(configuration.healthTargets.exerciseMinutes.mean, 15)

            let aggregate = HealthKitDailyAggregateData(
                userId: demoUser.id.uuidString,
                dayKey: dayKey(for: dayStart),
                dayStart: dayStart,
                steps: max(0, round(steps)),
                activeEnergyKcal: max(0, round(active)),
                restingEnergyKcal: max(0, round(resting)),
                exerciseMinutes: max(0, round(exerciseMinutes)),
                standHours: standHours,
                moveGoalKcal: moveGoal,
                exerciseGoalMinutes: exerciseGoal,
                standGoalHours: 12,
                sleepSeconds: max(0, sleepHours * 3600),
                bodyWeightKg: max(0, (weightKg * 10).rounded() / 10),
                schemaVersion: HealthKitDailyAggregateData.currentSchemaVersion,
                lastRefreshedAt: Date(),
                isToday: calendar.isDateInToday(dayStart)
            )
            modelContext.insert(aggregate)
        }

        try modelContext.save()
        return dayStarts.count
    }

    private func metricValue(
        setting: DemoMetricTargetSetting,
        dayIndex: Int,
        scale: Double,
        weeklyAmplitude: Double,
        correlation: Double = 0
    ) -> Double {
        let weekly = sin(Double(dayIndex) * (2 * .pi / 7)) * setting.range * weeklyAmplitude
        let random = signedNoise(dayIndex: dayIndex, salt: 97) * setting.range * scale
        let base = setting.mean + weekly + random + correlation
        let minValue = setting.mean - setting.range
        let maxValue = setting.mean + setting.range
        return min(max(base, minValue), maxValue)
    }

    private func routineTemplateNote(for routineName: String, dayIndex: Int) -> String {
        let suffixes = [
            "Felt strong throughout.",
            "Kept rest times tight.",
            "Focused on form today.",
            "Good session pace."
        ]
        return "\(routineName) session. \(suffixes[dayIndex % suffixes.count])"
    }

    private func shouldCreateSession(dayIndex: Int, noise: DemoNoisePreset) -> Bool {
        let weekday = dayIndex % 7
        if weekday == 1 || weekday == 3 || weekday == 5 {
            return true
        }
        if weekday == 6 {
            return probabilityHit(0.35, dayIndex: dayIndex, scale: noise.sessionScale)
        }
        return probabilityHit(0.18, dayIndex: dayIndex, scale: noise.sessionScale)
    }

    private func probabilityHit(_ probability: Double, dayIndex: Int, scale: Double) -> Bool {
        guard probability > 0 else { return false }
        let threshold = min(max(probability + signedNoise(dayIndex: dayIndex, salt: 211) * 0.08 * scale, 0), 1)
        return normalizedNoise(dayIndex: dayIndex, salt: 17) <= threshold
    }

    private func dateSeries(days: Int) -> [Date] {
        let normalizedDays = max(days, 1)
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -(normalizedDays - 1), to: end) ?? end
        return (0..<normalizedDays).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func pickValue<T>(_ values: [T], dayIndex: Int) -> T? {
        guard !values.isEmpty else { return nil }
        return values[abs(dayIndex) % values.count]
    }

    private func interpolatedValue(dayIndex: Int, minValue: Double, maxValue: Double, amplitude: Double) -> Double {
        guard maxValue > minValue else { return minValue }
        let center = (minValue + maxValue) / 2
        let range = (maxValue - minValue) / 2
        let wave = sin(Double(dayIndex) * 0.9) * range * 0.55
        let random = signedNoise(dayIndex: dayIndex, salt: 53) * range * amplitude
        let value = center + wave + random
        return min(max(value, minValue), maxValue)
    }

    private func normalizedNoise(dayIndex: Int, salt: Int) -> Double {
        var value = UInt64(bitPattern: Int64(dayIndex &* 1103515245 &+ salt &* 12345 &+ 67890))
        value ^= value >> 33
        value &*= 0xff51afd7ed558ccd
        value ^= value >> 33
        let normalized = Double(value % 10_000) / 10_000
        return normalized
    }

    private func signedNoise(dayIndex: Int, salt: Int) -> Double {
        (normalizedNoise(dayIndex: dayIndex, salt: salt) * 2) - 1
    }

    private func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func allUsers() throws -> [User] {
        try modelContext.fetch(FetchDescriptor<User>(sortBy: [SortDescriptor(\.lastLogin, order: .reverse)]))
    }

    private func demoExerciseCount(for user: User) -> Int {
        ((try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []).filter { $0.user_id == user.id }.count
    }
}
