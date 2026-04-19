//
//  ProgressionService.swift
//  GymTracker
//
//  Created by Codex on 2026-04-19.
//

import Combine
import Foundation
import SwiftData

private struct BundledProgressionProfileDefinition: Decodable {
    let name: String
    let miniDescription: String
    let type: String
    let incrementValue: Double
    let percentageIncrease: Double?
    let incrementUnitRaw: Int
    let setIncrement: Int
    let successThreshold: Int
    let defaultSetsTarget: Int
    let defaultRepsTarget: Int?
    let defaultRepsLow: Int?
    let defaultRepsHigh: Int?
}

private struct ProgressionWeightRecommendation {
    let exactWeight: Double?
    let lowerWeight: Double?
    let upperWeight: Double?
    let unit: WeightUnit?

    static let empty = ProgressionWeightRecommendation(
        exactWeight: nil,
        lowerWeight: nil,
        upperWeight: nil,
        unit: nil
    )
}

private struct ResolvedProgressionAssignment {
    let profile: ProgressionProfile
    let source: ProgressionAssignmentSource
}

final class ProgressionService: ServiceBase, ObservableObject {
    @Published var profiles: [ProgressionProfile] = []
    @Published var archivedProfiles: [ProgressionProfile] = []
    @Published var progressionExercises: [ProgressionExercise] = []

    private let repository: ProgressionRepositoryProtocol
    private let historyRepository: SessionRepositoryProtocol
    private let userRepository: UserRepositoryProtocol
    private var hasSeededBuiltIns = false

    init(
        context: ModelContext,
        repository: ProgressionRepositoryProtocol? = nil,
        historyRepository: SessionRepositoryProtocol? = nil,
        userRepository: UserRepositoryProtocol? = nil
    ) {
        self.repository = repository ?? LocalProgressionRepository(modelContext: context)
        self.historyRepository = historyRepository ?? LocalSessionRepository(modelContext: context)
        self.userRepository = userRepository ?? LocalUserRepository(modelContext: context)
        super.init(context: context)
    }

    override func loadFeature() {
        ensureBuiltInProfiles()
        loadProfiles()
        loadProgressionExercises()
    }

    func loadProfiles() {
        do {
            profiles = try repository.fetchAvailableProfiles(for: currentUser?.id)
            archivedProfiles = try repository.fetchArchivedProfiles(for: currentUser?.id)
        } catch {
            profiles = []
            archivedProfiles = []
        }
    }

    func loadProgressionExercises() {
        guard let userId = currentUser?.id else {
            progressionExercises = []
            return
        }

        do {
            progressionExercises = try repository.fetchProgressionExercises(for: userId)
        } catch {
            progressionExercises = []
        }
    }

    func ensureBuiltInProfiles() {
        guard !hasSeededBuiltIns else { return }
        defer { hasSeededBuiltIns = true }

        let definitions = loadBundledProfileDefinitions()
        for definition in definitions {
            guard let type = ProgressionType(rawValue: definition.type) else { continue }
            let incrementUnit = WeightUnit(rawValue: definition.incrementUnitRaw) ?? .lb

            do {
                _ = try repository.upsertBuiltInProfile(
                    name: definition.name,
                    miniDescription: definition.miniDescription,
                    type: type,
                    incrementValue: definition.incrementValue,
                    percentageIncrease: max(definition.percentageIncrease ?? 0, 0),
                    incrementUnit: incrementUnit,
                    setIncrement: definition.setIncrement,
                    successThreshold: definition.successThreshold,
                    defaultSetsTarget: definition.defaultSetsTarget,
                    defaultRepsTarget: definition.defaultRepsTarget,
                    defaultRepsLow: definition.defaultRepsLow,
                    defaultRepsHigh: definition.defaultRepsHigh
                )
            } catch {
                print("Failed to seed progression profile \(definition.name): \(error)")
            }
        }
    }

    @discardableResult
    func createProfile(
        name: String,
        miniDescription: String,
        type: ProgressionType,
        incrementValue: Double,
        percentageIncrease: Double,
        incrementUnit: WeightUnit,
        setIncrement: Int,
        successThreshold: Int,
        defaultSetsTarget: Int,
        defaultRepsTarget: Int?,
        defaultRepsLow: Int?,
        defaultRepsHigh: Int?
    ) -> ProgressionProfile? {
        guard let userId = currentUser?.id else { return nil }

        do {
            let profile = try repository.createProfile(
                userId: userId,
                name: name,
                miniDescription: miniDescription,
                type: type,
                incrementValue: incrementValue,
                percentageIncrease: percentageIncrease,
                incrementUnit: incrementUnit,
                setIncrement: setIncrement,
                successThreshold: successThreshold,
                defaultSetsTarget: defaultSetsTarget,
                defaultRepsTarget: defaultRepsTarget,
                defaultRepsLow: defaultRepsLow,
                defaultRepsHigh: defaultRepsHigh
            )
            loadProfiles()
            return profile
        } catch {
            print("Failed to create progression profile: \(error)")
            return nil
        }
    }

    func saveChanges(for profile: ProgressionProfile) {
        do {
            try repository.saveChanges(for: profile)
            loadProfiles()
        } catch {
            print("Failed to save progression profile: \(error)")
        }
    }

    func delete(_ profile: ProgressionProfile) {
        do {
            try repository.delete(profile)
            loadProfiles()
        } catch {
            print("Failed to delete progression profile: \(error)")
        }
    }

    func profile(id: UUID?) -> ProgressionProfile? {
        guard let id else { return nil }
        return profiles.first(where: { $0.id == id }) ??
            archivedProfiles.first(where: { $0.id == id }) ??
            (try? repository.fetchProfile(id: id))
    }

    func progressionExercise(for exerciseId: UUID) -> ProgressionExercise? {
        progressionExercises.first(where: { $0.exerciseId == exerciseId })
    }

    func exerciseOverride(for exerciseId: UUID) -> ProgressionExercise? {
        progressionExercises.first(where: { $0.exerciseId == exerciseId && $0.isExplicitOverride })
    }

    var globalProgressionEnabled: Bool {
        currentUser?.globalProgressionEnabled ?? false
    }

    var globalDefaultProfileId: UUID? {
        currentUser?.defaultProgressionProfileId
    }

    func profile(for progressionExercise: ProgressionExercise) -> ProgressionProfile? {
        profile(id: progressionExercise.progressionProfileId)
    }

    func saveGlobalDefaults(enabled: Bool, defaultProfileId: UUID?) {
        guard let currentUser else { return }

        objectWillChange.send()
        currentUser.globalProgressionEnabled = enabled
        currentUser.defaultProgressionProfileId = defaultProfileId
        currentUser.updatedAt = Date()

        do {
            try userRepository.saveChanges(for: currentUser)
        } catch {
            print("Failed to save global progression defaults: \(error)")
        }
    }

    @discardableResult
    func assignProgression(
        to exercise: Exercise,
        profile: ProgressionProfile?,
        assignmentSource: ProgressionAssignmentSource = .exerciseOverride,
        targetSets: Int? = nil,
        targetReps: Int? = nil,
        targetRepsLow: Int? = nil,
        targetRepsHigh: Int? = nil
    ) -> ProgressionExercise? {
        guard let userId = currentUser?.id else { return nil }

        let resolvedSetCount = max(targetSets ?? profile?.defaultSetsTarget ?? 3, 1)
        let resolvedLow = targetRepsLow ?? profile?.defaultRepsLow
        let resolvedHigh = targetRepsHigh ?? profile?.defaultRepsHigh
        let resolvedTarget = resolvedTargetReps(
            explicitTarget: targetReps,
            fallbackLow: resolvedLow,
            fallbackHigh: resolvedHigh,
            profile: profile
        )

        do {
            let progressionExercise: ProgressionExercise
            if let existing = try repository.fetchProgressionExercise(for: userId, exerciseId: exercise.id) {
                existing.exerciseNameSnapshot = exercise.name
                existing.progressionProfileId = profile?.id
                existing.progressionNameSnapshot = profile?.name
                existing.progressionMiniDescriptionSnapshot = profile?.miniDescription
                existing.progressionType = profile?.type
                existing.assignmentSource = assignmentSource
                existing.targetSetCount = resolvedSetCount
                existing.targetReps = resolvedTarget
                existing.targetRepsLow = resolvedLow
                existing.targetRepsHigh = resolvedHigh
                if let profile {
                    existing.workingWeightUnit = profile.incrementUnit
                }
                try repository.saveChanges(for: existing)
                progressionExercise = existing
            } else {
                progressionExercise = try repository.createProgressionExercise(
                    userId: userId,
                    exercise: exercise,
                    profile: profile,
                    assignmentSource: assignmentSource,
                    targetSetCount: resolvedSetCount,
                    targetReps: resolvedTarget,
                    targetRepsLow: resolvedLow,
                    targetRepsHigh: resolvedHigh
                )
            }

            backfillIfNeeded(for: progressionExercise, exercise: exercise)
            loadProgressionExercises()
            return progressionExercise
        } catch {
            print("Failed to assign progression: \(error)")
            return nil
        }
    }

    func removeProgression(from exercise: Exercise) {
        guard let userId = currentUser?.id else { return }

        do {
            if let progressionExercise = try repository.fetchProgressionExercise(for: userId, exerciseId: exercise.id),
               progressionExercise.isExplicitOverride {
                try repository.delete(progressionExercise)
                loadProgressionExercises()
            }
        } catch {
            print("Failed to remove progression: \(error)")
        }
    }

    func applySnapshots(to session: Session) {
        var didMutate = false
        for sessionEntry in session.sessionEntries {
            didMutate = applySnapshot(to: sessionEntry) || didMutate
        }

        if didMutate {
            try? historyRepository.saveChanges(for: session)
        }
    }

    @discardableResult
    func applySnapshot(to sessionEntry: SessionEntry) -> Bool {
        guard let progressionExercise = ensuredProgressionExercise(for: sessionEntry) else {
            if sessionEntry.hasProgressionSnapshot {
                sessionEntry.clearProgressionSnapshot()
                return true
            }
            return false
        }

        let profile = profile(for: progressionExercise)
        let recommendation = recommendedWeight(for: progressionExercise, exercise: sessionEntry.exercise)
        let didChange = sessionEntry.applyProgressionSnapshot(
            progressionExercise: progressionExercise,
            profile: profile,
            suggestedWeight: recommendation.exactWeight,
            suggestedWeightLow: recommendation.lowerWeight,
            suggestedWeightHigh: recommendation.upperWeight,
            suggestedWeightUnit: recommendation.unit,
            cycleSummary: cycleSummary(for: progressionExercise, profile: profile, recommendation: recommendation)
        )
        return didChange
    }

    func evaluateIfNeeded(for session: Session) {
        guard session.timestampDone != session.timestamp else { return }

        var didChange = false

        for sessionEntry in session.sessionEntries {
            guard sessionEntry.hasProgressionSnapshot else { continue }
            guard let progressionExercise = ensuredProgressionExercise(for: sessionEntry) ??
                progressionExercise(for: sessionEntry.exercise.id) else {
                continue
            }
            guard progressionExercise.lastEvaluatedSessionId != session.id else { continue }

            let profile = profile(for: progressionExercise)
            let actualWeight = bestActualWeight(for: sessionEntry)
            let success = entrySucceeded(sessionEntry)

            didChange = syncWorkingWeightIfNeeded(
                progressionExercise: progressionExercise,
                profile: profile,
                actualWeight: actualWeight
            ) || didChange

            if success {
                advance(progressionExercise: progressionExercise, profile: profile, actualWeight: actualWeight)
                didChange = true
            } else if progressionExercise.successCount != 0 {
                progressionExercise.successCount = 0
                didChange = true
            }

            progressionExercise.lastEvaluatedSessionId = session.id
            do {
                try repository.saveChanges(for: progressionExercise)
            } catch {
                print("Failed to save progression evaluation: \(error)")
            }
        }

        if didChange {
            loadProgressionExercises()
        }
    }

    private func ensuredProgressionExercise(for sessionEntry: SessionEntry) -> ProgressionExercise? {
        if let explicitOverride = exerciseOverride(for: sessionEntry.exercise.id) {
            return explicitOverride
        }

        guard let resolvedAssignment = defaultAssignment(for: sessionEntry) else { return nil }

        if let existing = progressionExercise(for: sessionEntry.exercise.id) {
            return syncInheritedProgressionExercise(
                existing,
                exercise: sessionEntry.exercise,
                resolvedAssignment: resolvedAssignment
            )
        }

        return assignProgression(
            to: sessionEntry.exercise,
            profile: resolvedAssignment.profile,
            assignmentSource: resolvedAssignment.source,
            targetSets: nil,
            targetReps: nil,
            targetRepsLow: nil,
            targetRepsHigh: nil
        )
    }

    private func defaultAssignment(for sessionEntry: SessionEntry) -> ResolvedProgressionAssignment? {
        if let program = sessionEntry.session.program {
            if let programProfile = profile(id: program.defaultProgressionProfileId) {
                return ResolvedProgressionAssignment(
                    profile: programProfile,
                    source: .programDefault
                )
            }
            return fallbackUserAssignment()
        }

        if let routine = sessionEntry.session.routine {
            if let routineProfile = profile(id: routine.defaultProgressionProfileId) {
                return ResolvedProgressionAssignment(
                    profile: routineProfile,
                    source: .routineDefault
                )
            }
            return fallbackUserAssignment()
        }

        return fallbackUserAssignment()
    }

    private func fallbackUserAssignment() -> ResolvedProgressionAssignment? {
        guard globalProgressionEnabled,
              let userProfile = profile(id: globalDefaultProfileId) else {
            return nil
        }

        return ResolvedProgressionAssignment(
            profile: userProfile,
            source: .userDefault
        )
    }

    private func syncInheritedProgressionExercise(
        _ progressionExercise: ProgressionExercise,
        exercise: Exercise,
        resolvedAssignment: ResolvedProgressionAssignment
    ) -> ProgressionExercise {
        guard !progressionExercise.isExplicitOverride else { return progressionExercise }

        let profile = resolvedAssignment.profile
        let profileChanged = progressionExercise.progressionProfileId != profile.id
        var didChange = false

        progressionExercise.exerciseNameSnapshot = exercise.name

        if progressionExercise.assignmentSource != resolvedAssignment.source {
            progressionExercise.assignmentSource = resolvedAssignment.source
            didChange = true
        }

        if profileChanged {
            progressionExercise.progressionProfileId = profile.id
            progressionExercise.progressionNameSnapshot = profile.name
            progressionExercise.progressionMiniDescriptionSnapshot = profile.miniDescription
            progressionExercise.progressionType = profile.type
            progressionExercise.targetSetCount = max(profile.defaultSetsTarget, 1)
            progressionExercise.targetRepsLow = profile.defaultRepsLow
            progressionExercise.targetRepsHigh = profile.defaultRepsHigh
            progressionExercise.targetReps = resolvedTargetReps(
                explicitTarget: profile.defaultRepsTarget,
                fallbackLow: profile.defaultRepsLow,
                fallbackHigh: profile.defaultRepsHigh,
                profile: profile
            )
            progressionExercise.workingWeight = nil
            progressionExercise.suggestedWeightLow = nil
            progressionExercise.suggestedWeightHigh = nil
            progressionExercise.lastCompletedCycleWeight = nil
            progressionExercise.lastCompletedCycleReps = nil
            progressionExercise.lastCompletedCycleUnit = nil
            progressionExercise.successCount = 0
            progressionExercise.hasBackfilled = false
            progressionExercise.backfilledAt = nil
            progressionExercise.lastEvaluatedSessionId = nil
            progressionExercise.workingWeightUnit = profile.incrementUnit
            didChange = true
        }

        if didChange {
            do {
                try repository.saveChanges(for: progressionExercise)
            } catch {
                print("Failed to sync inherited progression exercise: \(error)")
            }
        }

        backfillIfNeeded(for: progressionExercise, exercise: exercise)
        if didChange {
            loadProgressionExercises()
        }

        return progressionExercise
    }

    private func backfillIfNeeded(for progressionExercise: ProgressionExercise, exercise: Exercise) {
        guard !progressionExercise.hasBackfilled else { return }

        if let rep = historyRepository.mostRecentRep(for: exercise) {
            progressionExercise.workingWeight = rep.weight
            progressionExercise.workingWeightUnit = rep.weightUnit
            progressionExercise.suggestedWeightLow = nil
            progressionExercise.suggestedWeightHigh = nil
        }
        progressionExercise.successCount = 0
        progressionExercise.hasBackfilled = true
        progressionExercise.backfilledAt = Date()

        do {
            try repository.saveChanges(for: progressionExercise)
        } catch {
            print("Failed to save progression backfill: \(error)")
        }
    }

    private func recommendedWeight(
        for progressionExercise: ProgressionExercise,
        exercise: Exercise
    ) -> ProgressionWeightRecommendation {
        if let workingWeight = progressionExercise.workingWeight {
            return ProgressionWeightRecommendation(
                exactWeight: workingWeight,
                lowerWeight: nil,
                upperWeight: nil,
                unit: progressionExercise.workingWeightUnit
            )
        }

        if let suggestedWeightLow = progressionExercise.suggestedWeightLow ?? progressionExercise.suggestedWeightHigh {
            let suggestedWeightHigh = progressionExercise.suggestedWeightHigh ?? suggestedWeightLow
            if suggestedWeightLow == suggestedWeightHigh {
                return ProgressionWeightRecommendation(
                    exactWeight: suggestedWeightLow,
                    lowerWeight: nil,
                    upperWeight: nil,
                    unit: progressionExercise.workingWeightUnit
                )
            }

            return ProgressionWeightRecommendation(
                exactWeight: nil,
                lowerWeight: min(suggestedWeightLow, suggestedWeightHigh),
                upperWeight: max(suggestedWeightLow, suggestedWeightHigh),
                unit: progressionExercise.workingWeightUnit
            )
        }

        if let rep = historyRepository.mostRecentRep(for: exercise) {
            return ProgressionWeightRecommendation(
                exactWeight: rep.weight,
                lowerWeight: nil,
                upperWeight: nil,
                unit: rep.weightUnit
            )
        }

        return .empty
    }

    private func cycleSummary(
        for progressionExercise: ProgressionExercise,
        profile: ProgressionProfile?,
        recommendation: ProgressionWeightRecommendation
    ) -> String? {
        let resolvedType = profile?.type ?? progressionExercise.progressionType ?? .linear
        let targetSets = max(progressionExercise.targetSetCount, 1)
        let repsRangeText = ProgressionDisplayFormatter.repsSummary(
            targetReps: nil,
            targetRepsLow: progressionExercise.targetRepsLow,
            targetRepsHigh: progressionExercise.targetRepsHigh
        )
        let goalRepText = "\(progressionExercise.targetReps ?? progressionExercise.targetRepsLow ?? progressionExercise.targetRepsHigh ?? 0)"
        let weightText = ProgressionDisplayFormatter.weightSummary(
            weight: recommendation.exactWeight,
            low: recommendation.lowerWeight,
            high: recommendation.upperWeight,
            unit: recommendation.unit
        )

        switch resolvedType {
        case .linear:
            if let weightText {
                return "Hit \(targetSets) set\(targetSets == 1 ? "" : "s") at \(goalRepText) reps, then add load. Current target: \(weightText)."
            }
            return "Hit \(targetSets) set\(targetSets == 1 ? "" : "s") at \(goalRepText) reps, then add load."

        case .doubleProgression:
            if progressionExercise.workingWeight == nil,
               let weightText {
                if let lastCompletedText = ProgressionDisplayFormatter.weightSummary(
                    weight: progressionExercise.lastCompletedCycleWeight,
                    unit: progressionExercise.lastCompletedCycleUnit
                ) {
                    let topReps = progressionExercise.lastCompletedCycleReps ?? progressionExercise.targetRepsHigh ?? progressionExercise.targetReps ?? 0
                    return "Last cycle topped out at \(lastCompletedText) x \(topReps). Choose \(weightText) and restart at \(goalRepText) reps."
                }
                return "Choose \(weightText) and restart at \(goalRepText) reps."
            }

            if let weightText {
                return "Current cycle: \(weightText) for \(targetSets) x \(repsRangeText). Goal this time: \(goalRepText) reps on every set."
            }
            return "Build each set through the \(repsRangeText) range. Goal this time: \(goalRepText) reps."

        case .volume:
            if let weightText {
                return "Keep \(weightText) steady and build up to \(targetSets) total sets."
            }
            return "Keep the load steady and build up to \(targetSets) total sets."
        }
    }

    private func loadBundledProfileDefinitions() -> [BundledProgressionProfileDefinition] {
        let candidateURLs: [URL?] = [
            Bundle.main.url(forResource: "default_progression_profiles", withExtension: "json", subdirectory: "Features/Progression"),
            Bundle.main.url(forResource: "default_progression_profiles", withExtension: "json")
        ]

        guard let url = candidateURLs.compactMap({ $0 }).first else {
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([BundledProgressionProfileDefinition].self, from: data)
        } catch {
            print("Failed to load bundled progression profiles: \(error)")
            return []
        }
    }

    private func resolvedTargetReps(
        explicitTarget: Int?,
        fallbackLow: Int?,
        fallbackHigh: Int?,
        profile: ProgressionProfile?
    ) -> Int? {
        if let explicitTarget {
            return explicitTarget
        }

        if let fallbackLow {
            return fallbackLow
        }

        if let profile, let target = profile.defaultRepsTarget {
            return target
        }

        return fallbackHigh
    }

    private func entrySucceeded(_ sessionEntry: SessionEntry) -> Bool {
        let targetSetCount = max(sessionEntry.appliedTargetSetCount ?? 0, 1)
        let requiredReps = sessionEntry.appliedTargetReps ??
            sessionEntry.appliedTargetRepsHigh ??
            sessionEntry.appliedTargetRepsLow

        let meaningfulSetValues = sessionEntry.sets
            .sorted { $0.order < $1.order }
            .filter { SetDisplayFormatter.isMeaningfulSet($0, exerciseKind: sessionEntry.exercise.setDisplayKind) }
            .prefix(targetSetCount)
            .compactMap { bestRepCount(in: $0) }

        guard meaningfulSetValues.count >= targetSetCount else { return false }
        guard let requiredReps else { return true }
        return meaningfulSetValues.allSatisfy { $0 >= requiredReps }
    }

    private func bestRepCount(in sessionSet: SessionSet) -> Int? {
        let reps = sessionSet.sessionReps.map(\.count).filter { $0 > 0 }
        return reps.max()
    }

    private func bestActualWeight(for sessionEntry: SessionEntry) -> (weight: Double, unit: WeightUnit)? {
        let samples = sessionEntry.sets
            .flatMap(\.sessionReps)
            .filter { $0.weight > 0 }

        guard let bestRep = samples.max(by: { lhs, rhs in
            let lhsLb = lhs.weight * lhs.weightUnit.conversion(to: .lb)
            let rhsLb = rhs.weight * rhs.weightUnit.conversion(to: .lb)
            return lhsLb < rhsLb
        }) else {
            return nil
        }

        return (bestRep.weight, bestRep.weightUnit)
    }

    private func syncWorkingWeightIfNeeded(
        progressionExercise: ProgressionExercise,
        profile: ProgressionProfile?,
        actualWeight: (weight: Double, unit: WeightUnit)?
    ) -> Bool {
        guard let actualWeight else { return false }

        let currentLb = progressionExercise.workingWeight.map {
            $0 * progressionExercise.workingWeightUnit.conversion(to: .lb)
        }
        let actualLb = actualWeight.weight * actualWeight.unit.conversion(to: .lb)

        if currentLb == nil || abs((currentLb ?? 0) - actualLb) > 0.05 {
            progressionExercise.workingWeight = actualWeight.weight
            progressionExercise.workingWeightUnit = actualWeight.unit
            progressionExercise.suggestedWeightLow = nil
            progressionExercise.suggestedWeightHigh = nil
            if profile?.type == .doubleProgression || progressionExercise.progressionType == .doubleProgression {
                return true
            }
            return currentLb == nil
        }

        return false
    }

    private func advance(
        progressionExercise: ProgressionExercise,
        profile: ProgressionProfile?,
        actualWeight: (weight: Double, unit: WeightUnit)?
    ) {
        let resolvedType = profile?.type ?? progressionExercise.progressionType ?? .linear
        let resolvedThreshold = max(profile?.successThreshold ?? 1, 1)

        switch resolvedType {
        case .linear:
            progressionExercise.successCount += 1
            if progressionExercise.successCount >= resolvedThreshold {
                applyWeightIncrement(
                    progressionExercise: progressionExercise,
                    profile: profile,
                    actualWeight: actualWeight
                )
                progressionExercise.successCount = 0
            }

        case .doubleProgression:
            advanceDoubleProgression(
                progressionExercise: progressionExercise,
                profile: profile,
                actualWeight: actualWeight
            )

        case .volume:
            progressionExercise.successCount += 1
            if progressionExercise.successCount >= resolvedThreshold {
                progressionExercise.targetSetCount += max(profile?.setIncrement ?? 1, 1)
                progressionExercise.successCount = 0
            }
        }
    }

    private func advanceDoubleProgression(
        progressionExercise: ProgressionExercise,
        profile: ProgressionProfile?,
        actualWeight: (weight: Double, unit: WeightUnit)?
    ) {
        let low = progressionExercise.targetRepsLow ?? progressionExercise.targetReps ?? 8
        let high = progressionExercise.targetRepsHigh ?? progressionExercise.targetReps ?? max(low, 10)
        let current = progressionExercise.targetReps ?? low

        if current < high {
            progressionExercise.targetReps = current + 1
            progressionExercise.successCount = 0
            return
        }

        let completedWeight = actualWeight?.weight ?? progressionExercise.workingWeight
        let completedUnit = actualWeight?.unit ?? progressionExercise.workingWeightUnit
        if let completedWeight {
            progressionExercise.lastCompletedCycleWeight = completedWeight
            progressionExercise.lastCompletedCycleUnit = completedUnit
            progressionExercise.lastCompletedCycleReps = high
        }

        let recommendation = nextDoubleProgressionWeightRecommendation(
            progressionExercise: progressionExercise,
            profile: profile,
            actualWeight: actualWeight
        )

        progressionExercise.workingWeight = nil
        if let unit = recommendation.unit {
            progressionExercise.workingWeightUnit = unit
        }
        progressionExercise.suggestedWeightLow = recommendation.lowerWeight ?? recommendation.exactWeight
        progressionExercise.suggestedWeightHigh = recommendation.upperWeight ?? recommendation.exactWeight
        progressionExercise.targetReps = low
        progressionExercise.successCount = 0
    }

    private func nextDoubleProgressionWeightRecommendation(
        progressionExercise: ProgressionExercise,
        profile: ProgressionProfile?,
        actualWeight: (weight: Double, unit: WeightUnit)?
    ) -> ProgressionWeightRecommendation {
        let baseWeight = actualWeight?.weight ?? progressionExercise.workingWeight
        let unit = actualWeight?.unit ?? progressionExercise.workingWeightUnit
        guard let baseWeight else { return .empty }

        let leastIncrease = leastObservedWeightIncrease(
            for: progressionExercise.exerciseId,
            targetUnit: unit
        ) ?? fallbackAbsoluteIncrement(profile: profile, targetUnit: unit)
        let percentageIncrease = percentageIncrement(profile: profile, baseWeight: baseWeight)

        let candidates = [leastIncrease, percentageIncrease]
            .compactMap { $0 }
            .map { normalizeWeight(baseWeight + $0) }
            .filter { $0 > baseWeight }
            .sorted()

        guard let first = candidates.first else {
            return .empty
        }

        let last = candidates.last ?? first
        if first == last {
            return ProgressionWeightRecommendation(
                exactWeight: first,
                lowerWeight: nil,
                upperWeight: nil,
                unit: unit
            )
        }

        return ProgressionWeightRecommendation(
            exactWeight: nil,
            lowerWeight: first,
            upperWeight: last,
            unit: unit
        )
    }

    private func fallbackAbsoluteIncrement(profile: ProgressionProfile?, targetUnit: WeightUnit) -> Double? {
        let incrementValue = profile?.incrementValue ?? 0
        guard incrementValue > 0 else { return nil }
        let sourceUnit = profile?.incrementUnit ?? targetUnit
        return incrementValue * sourceUnit.conversion(to: targetUnit)
    }

    private func percentageIncrement(profile: ProgressionProfile?, baseWeight: Double) -> Double? {
        let percentage = profile?.percentageIncrease ?? 0
        guard percentage > 0, baseWeight > 0 else { return nil }
        return baseWeight * (percentage / 100)
    }

    private func leastObservedWeightIncrease(for exerciseId: UUID, targetUnit: WeightUnit) -> Double? {
        let reps = relevantStrengthReps(for: exerciseId)
        let weights = reps
            .map { normalizeWeight($0.weight * $0.weightUnit.conversion(to: targetUnit)) }
            .filter { $0 > 0 }

        let uniqueWeights = Array(Set(weights)).sorted()
        guard uniqueWeights.count > 1 else { return nil }

        let increments = zip(uniqueWeights.dropFirst(), uniqueWeights)
            .map { normalizeWeight($0.0 - $0.1) }
            .filter { $0 > 0 }

        return increments.min()
    }

    private func relevantStrengthReps(for exerciseId: UUID) -> [SessionRep] {
        let descriptor = FetchDescriptor<SessionEntry>()
        let entries = (try? modelContext.fetch(descriptor)) ?? []

        return entries
            .filter { entry in
                entry.exercise.id == exerciseId &&
                entry.session.soft_deleted == false &&
                entry.exercise.cardio == false
            }
            .flatMap { entry in
                entry.sets
                    .filter { SetDisplayFormatter.isMeaningfulSet($0, exerciseKind: entry.exercise.setDisplayKind) }
                    .flatMap(\.sessionReps)
            }
            .filter { $0.weight > 0 && $0.count > 0 }
    }

    private func applyWeightIncrement(
        progressionExercise: ProgressionExercise,
        profile: ProgressionProfile?,
        actualWeight: (weight: Double, unit: WeightUnit)?
    ) {
        let unit = actualWeight?.unit ?? progressionExercise.workingWeightUnit
        let baseWeight = progressionExercise.workingWeight ?? actualWeight?.weight
        guard let baseWeight else { return }

        let incrementValue = fallbackAbsoluteIncrement(profile: profile, targetUnit: unit) ?? 0
        progressionExercise.workingWeightUnit = unit
        progressionExercise.workingWeight = normalizeWeight(max(baseWeight + incrementValue, 0))
        progressionExercise.suggestedWeightLow = nil
        progressionExercise.suggestedWeightHigh = nil
    }

    private func normalizeWeight(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
