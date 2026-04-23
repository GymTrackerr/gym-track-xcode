import Foundation
import SwiftData

enum OnboardingPlanBuilderError: LocalizedError {
    case missingTemplate
    case noExercisesAvailable
    case noGeneratedRoutines
    case invalidWeeklySchedule
    case missingUser

    var errorDescription: String? {
        switch self {
        case .missingTemplate:
            return "We could not find a matching routine template."
        case .noExercisesAvailable:
            return "There are no exercises available yet to build this routine."
        case .noGeneratedRoutines:
            return "We could not generate a routine from the available exercises."
        case .invalidWeeklySchedule:
            return "The weekly schedule needs one unique weekday for each routine."
        case .missingUser:
            return "There is no active user for this onboarding step."
        }
    }
}

enum OnboardingTemplateLoaderError: LocalizedError {
    case missingTemplate(String)
    case invalidTemplate(String)

    var errorDescription: String? {
        switch self {
        case .missingTemplate(let resource):
            return "Could not find bundled onboarding template '\(resource)'."
        case .invalidTemplate(let resource):
            return "The bundled onboarding template '\(resource)' could not be decoded."
        }
    }
}

enum OnboardingTemplateLoader {
    static func loadProgramTemplates() throws -> OnboardingProgramTemplateBundle {
        try load("onboarding_program_templates", as: OnboardingProgramTemplateBundle.self)
    }

    private static func load<T: Decodable>(_ resource: String, as type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys

        let candidateURLs: [URL?] = [
            Bundle.main.url(forResource: resource, withExtension: "json", subdirectory: "Features/Onboarding"),
            Bundle.main.url(forResource: resource, withExtension: "json")
        ]

        guard let url = candidateURLs.compactMap({ $0 }).first else {
            throw OnboardingTemplateLoaderError.missingTemplate(resource)
        }

        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(T.self, from: data)
        } catch let error as OnboardingTemplateLoaderError {
            throw error
        } catch {
            throw OnboardingTemplateLoaderError.invalidTemplate(resource)
        }
    }
}

@MainActor
final class OnboardingPlanBuilder {
    private let modelContext: ModelContext
    private let routineRepository: RoutineRepositoryProtocol
    private let programRepository: ProgramRepositoryProtocol

    init(
        context: ModelContext,
        routineRepository: RoutineRepositoryProtocol? = nil,
        programRepository: ProgramRepositoryProtocol? = nil
    ) {
        self.modelContext = context
        self.routineRepository = routineRepository ?? LocalRoutineRepository(modelContext: context)
        self.programRepository = programRepository ?? LocalProgramRepository(modelContext: context)
    }

    func loadTemplates() throws -> OnboardingProgramTemplateBundle {
        try OnboardingTemplateLoader.loadProgramTemplates()
    }

    func prepareGeneratedPreview(
        template: OnboardingProgramTemplate,
        exercises: [Exercise]
    ) throws -> OnboardingPlanPreview {
        let activeExercises = exercises.filter { !$0.isArchived }
        guard !activeExercises.isEmpty else {
            throw OnboardingPlanBuilderError.noExercisesAvailable
        }

        var routines: [OnboardingPlanPreviewRoutine] = []

        for (index, templateRoutine) in template.routines.enumerated() {
            var usedExerciseIds = Set<UUID>()
            var previewExercises: [OnboardingPlanPreviewExercise] = []
            var exerciseIds: [UUID] = []

            for slot in templateRoutine.slots {
                guard let exercise = selectExercise(
                    for: slot,
                    from: activeExercises,
                    excluding: usedExerciseIds
                ) else { continue }

                usedExerciseIds.insert(exercise.id)
                exerciseIds.append(exercise.id)
                previewExercises.append(
                    OnboardingPlanPreviewExercise(
                        id: exercise.id,
                        name: exercise.name,
                        detail: exerciseDetail(for: exercise)
                    )
                )
            }

            guard !previewExercises.isEmpty else { continue }

            let weekdayIndex = template.programMode == .weekly
                ? template.defaultWeekdays[safe: index]
                : nil

            routines.append(
                OnboardingPlanPreviewRoutine(
                    name: templateRoutine.name,
                    focusLabel: templateRoutine.focus,
                    weekdayIndex: weekdayIndex,
                    exerciseIds: exerciseIds,
                    exercises: previewExercises
                )
            )
        }

        guard !routines.isEmpty else {
            throw OnboardingPlanBuilderError.noGeneratedRoutines
        }

        return OnboardingPlanPreview(
            title: template.title,
            subtitle: template.subtitle,
            source: .generateRoutine,
            mode: template.programMode,
            trainDaysBeforeRest: template.trainDaysBeforeRest,
            restDays: template.restDays,
            routines: routines
        )
    }

    func prepareExistingPreview(
        name: String,
        mode: ProgramMode,
        routineDays: [OnboardingRoutineDayDraft],
        exercises: [Exercise],
        weeklyWeekdays: [ProgramWeekday],
        trainDaysBeforeRest: Int,
        restDays: Int
    ) throws -> OnboardingPlanPreview {
        let resolvedNames = resolvedRoutineNames(from: routineDays)
        let exerciseById = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })

        if mode == .weekly {
            let weekdayValues = weeklyWeekdays.map(\.rawValue)
            guard weekdayValues.count == routineDays.count,
                  Set(weekdayValues).count == weekdayValues.count else {
                throw OnboardingPlanBuilderError.invalidWeeklySchedule
            }
        }

        let routines: [OnboardingPlanPreviewRoutine] = resolvedNames.enumerated().map { index, resolvedName in
            let selectedExercises = routineDays[index].exerciseIds.compactMap { exerciseById[$0] }
            return OnboardingPlanPreviewRoutine(
                name: resolvedName,
                focusLabel: routineDays[index].focus == .custom ? nil : routineDays[index].focus.title,
                weekdayIndex: mode == .weekly ? weeklyWeekdays[index].rawValue : nil,
                exerciseIds: selectedExercises.map(\.id),
                exercises: selectedExercises.map { exercise in
                    OnboardingPlanPreviewExercise(
                        id: exercise.id,
                        name: exercise.name,
                        detail: exerciseDetail(for: exercise)
                    )
                }
            )
        }

        return OnboardingPlanPreview(
            title: name,
            subtitle: mode == .weekly
                ? "Review your weekly programme before saving it."
                : "Review your rotating programme before saving it.",
            source: .existingRoutine,
            mode: mode,
            trainDaysBeforeRest: trainDaysBeforeRest,
            restDays: restDays,
            routines: routines
        )
    }

    @discardableResult
    func persist(preview: OnboardingPlanPreview, for user: User) throws -> Program {
        let routines = try createRoutines(from: preview, for: user)

        let program = try programRepository.createProgram(
            userId: user.id,
            name: preview.title,
            notes: "",
            mode: preview.mode,
            startDate: Date(),
            trainDaysBeforeRest: preview.trainDaysBeforeRest,
            restDays: preview.restDays
        )

        let directBlock = try programRepository.addBlock(
            to: program,
            name: ProgramBlock.hiddenRepeatingBlockSentinel,
            durationCount: 0
        )

        for (index, routine) in routines.enumerated() {
            let weekdayIndex = preview.mode == .weekly
                ? preview.routines[safe: index]?.weekdayIndex
                : nil

            _ = try programRepository.addWorkout(
                to: directBlock,
                routine: routine,
                name: nil,
                weekdayIndex: weekdayIndex
            )
        }

        try programRepository.setActiveProgram(program)
        return program
    }

    private func createRoutines(from preview: OnboardingPlanPreview, for user: User) throws -> [Routine] {
        let exerciseById = try fetchExercises(for: user.id)
        var routines: [Routine] = []

        for (index, previewRoutine) in preview.routines.enumerated() {
            let routine = try routineRepository.createRoutine(
                name: previewRoutine.name,
                userId: user.id,
                order: index
            )

            for exerciseId in previewRoutine.exerciseIds {
                guard let exercise = exerciseById[exerciseId] else { continue }
                _ = try routineRepository.addExercise(to: routine, exercise: exercise)
            }

            routines.append(routine)
        }

        return routines
    }

    private func fetchExercises(for userId: UUID) throws -> [UUID: Exercise] {
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { exercise in
                exercise.user_id == userId && exercise.soft_deleted == false && exercise.isArchived == false
            }
        )

        return try modelContext.fetch(descriptor).reduce(into: [:]) { partialResult, exercise in
            partialResult[exercise.id] = exercise
        }
    }

    private func selectExercise(
        for slot: OnboardingProgramSlotTemplate,
        from exercises: [Exercise],
        excluding usedExerciseIds: Set<UUID>
    ) -> Exercise? {
        let available = exercises.filter { !usedExerciseIds.contains($0.id) }
        guard !available.isEmpty else { return nil }

        let normalizedPreferredNpIds = Set((slot.preferredNpIds ?? []).map { normalized($0) })
        if normalizedPreferredNpIds.isEmpty == false,
           let exactNpIdMatch = available.first(where: { exercise in
               guard let npId = exercise.npId else { return false }
               return normalizedPreferredNpIds.contains(normalized(npId))
           }) {
            return exactNpIdMatch
        }

        let normalizedTargetMuscles = slot.targetMuscles.map { normalized($0) }
        let scoredMuscleMatches = available
            .map { exercise in
                (exercise: exercise, score: muscleScore(for: exercise, targetMuscles: normalizedTargetMuscles, keywords: slot.keywords))
            }
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return lhs.exercise.name.localizedCaseInsensitiveCompare(rhs.exercise.name) == .orderedAscending
            }

        if let bestMuscleMatch = scoredMuscleMatches.first?.exercise {
            return bestMuscleMatch
        }

        let normalizedKeywords = slot.keywords.map { normalized($0) }
        if normalizedKeywords.isEmpty == false,
           let keywordMatch = available.first(where: { exercise in
               let haystack = searchableText(for: exercise)
               return normalizedKeywords.contains(where: { haystack.contains($0) })
           }) {
            return keywordMatch
        }

        let normalizedFallbackTypes = slot.fallbackTypes.map { normalized($0) }
        if normalizedFallbackTypes.isEmpty == false,
           let fallback = available.first(where: { exercise in
               let typeLabel = normalized(exercise.exerciseType.name)
               let category = normalized(exercise.category ?? "")
               return normalizedFallbackTypes.contains(where: { typeLabel.contains($0) || category.contains($0) })
           }) {
            return fallback
        }

        return available.first
    }

    private func muscleScore(
        for exercise: Exercise,
        targetMuscles: [String],
        keywords: [String]
    ) -> Int {
        let primaryMuscles = Set((exercise.primary_muscles ?? []).map { normalized($0) })
        let secondaryMuscles = Set((exercise.secondary_muscles ?? []).map { normalized($0) })
        let haystack = searchableText(for: exercise)

        var score = 0
        for muscle in targetMuscles {
            if primaryMuscles.contains(muscle) {
                score += 4
            } else if secondaryMuscles.contains(muscle) {
                score += 2
            }
        }

        for keyword in keywords.map({ normalized($0) }) where haystack.contains(keyword) {
            score += 1
        }

        if exercise.npId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            score += 1
        }

        return score
    }

    private func exerciseDetail(for exercise: Exercise) -> String {
        let muscles = (exercise.primary_muscles ?? []) + (exercise.secondary_muscles ?? [])
        let muscleSummary = muscles
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(2)
            .joined(separator: " / ")

        if muscleSummary.isEmpty == false {
            return muscleSummary
        }

        if let category = exercise.category?.trimmingCharacters(in: .whitespacesAndNewlines),
           !category.isEmpty {
            return category.capitalized
        }

        return exercise.exerciseType.name
    }

    private func searchableText(for exercise: Exercise) -> String {
        ([exercise.name] + (exercise.aliases ?? []) + (exercise.primary_muscles ?? []) + (exercise.secondary_muscles ?? []) + [exercise.category ?? "", exercise.equipment ?? ""])
            .joined(separator: " ")
            .lowercased()
    }

    private func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func resolvedRoutineNames(from drafts: [OnboardingRoutineDayDraft]) -> [String] {
        var countsByBaseName: [String: Int] = [:]
        let baseNames = drafts.map(\.preferredName)
        let duplicateNames = Dictionary(grouping: baseNames, by: { $0 })

        return drafts.map { draft in
            let baseName = draft.preferredName
            let duplicateCount = duplicateNames[baseName]?.count ?? 0
            guard duplicateCount > 1 else { return baseName }

            let nextIndex = countsByBaseName[baseName, default: 0] + 1
            countsByBaseName[baseName] = nextIndex
            return "\(baseName) \(alphabeticalSuffix(for: nextIndex))"
        }
    }

    private func alphabeticalSuffix(for index: Int) -> String {
        let clampedIndex = max(index, 1)
        if clampedIndex <= 26,
           let scalar = UnicodeScalar(64 + clampedIndex) {
            return String(Character(scalar))
        }

        return String(clampedIndex)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
