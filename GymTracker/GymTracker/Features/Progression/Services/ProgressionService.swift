//
//  ProgressionService.swift
//  GymTracker
//
//  Created by Codex on 2026-04-19.
//

import Foundation
import SwiftData
import Combine

private struct BundledProgressionProfileDefinition: Decodable {
    let name: String
    let miniDescription: String
    let type: String
    let incrementValue: Double
    let incrementUnitRaw: Int
    let setIncrement: Int
    let successThreshold: Int
    let defaultSetsTarget: Int
    let defaultRepsTarget: Int?
    let defaultRepsLow: Int?
    let defaultRepsHigh: Int?
}

final class ProgressionService: ServiceBase, ObservableObject {
    @Published var profiles: [ProgressionProfile] = []
    @Published var archivedProfiles: [ProgressionProfile] = []
    @Published var progressionExercises: [ProgressionExercise] = []

    private let repository: ProgressionRepositoryProtocol
    private let historyRepository: SessionRepositoryProtocol
    private var hasSeededBuiltIns = false

    init(
        context: ModelContext,
        repository: ProgressionRepositoryProtocol? = nil,
        historyRepository: SessionRepositoryProtocol? = nil
    ) {
        self.repository = repository ?? LocalProgressionRepository(modelContext: context)
        self.historyRepository = historyRepository ?? LocalSessionRepository(modelContext: context)
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

    func progressionExercise(for exerciseId: UUID) -> ProgressionExercise? {
        progressionExercises.first(where: { $0.exerciseId == exerciseId })
    }

    func profile(for progressionExercise: ProgressionExercise) -> ProgressionProfile? {
        guard let progressionProfileId = progressionExercise.progressionProfileId else { return nil }
        return profiles.first(where: { $0.id == progressionProfileId }) ??
            archivedProfiles.first(where: { $0.id == progressionProfileId }) ??
            (try? repository.fetchProfile(id: progressionProfileId))
    }

    @discardableResult
    func assignProgression(
        to exercise: Exercise,
        profile: ProgressionProfile?,
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
            if let progressionExercise = try repository.fetchProgressionExercise(for: userId, exerciseId: exercise.id) {
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
        guard let progressionExercise = progressionExercise(for: sessionEntry.exercise.id) else {
            if sessionEntry.hasProgressionSnapshot {
                sessionEntry.clearProgressionSnapshot()
                return true
            }
            return false
        }

        let suggestion = suggestedWeight(for: progressionExercise, exercise: sessionEntry.exercise)
        let didChange = sessionEntry.applyProgressionSnapshot(
            progressionExercise: progressionExercise,
            profile: profile(for: progressionExercise),
            suggestedWeight: suggestion.weight,
            suggestedWeightUnit: suggestion.unit
        )
        return didChange
    }

    func evaluateIfNeeded(for session: Session) {
        guard session.timestampDone != session.timestamp else { return }

        var didChange = false

        for sessionEntry in session.sessionEntries {
            guard let progressionExercise = progressionExercise(for: sessionEntry.exercise.id) else { continue }
            guard progressionExercise.lastEvaluatedSessionId != session.id else { continue }

            let success = entrySucceeded(sessionEntry)
            let profile = profile(for: progressionExercise)
            let actualWeight = bestActualWeight(for: sessionEntry)

            if progressionExercise.workingWeight == nil,
               let actualWeight {
                progressionExercise.workingWeight = actualWeight.weight
                progressionExercise.workingWeightUnit = actualWeight.unit
                didChange = true
            }

            if success {
                advance(progressionExercise: progressionExercise, profile: profile, actualWeight: actualWeight)
                didChange = true
            } else {
                if progressionExercise.successCount != 0 {
                    progressionExercise.successCount = 0
                    didChange = true
                }
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

    private func backfillIfNeeded(for progressionExercise: ProgressionExercise, exercise: Exercise) {
        guard !progressionExercise.hasBackfilled else { return }

        if let rep = historyRepository.mostRecentRep(for: exercise) {
            progressionExercise.workingWeight = rep.weight
            progressionExercise.workingWeightUnit = rep.weightUnit
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

    private func suggestedWeight(for progressionExercise: ProgressionExercise, exercise: Exercise) -> (weight: Double?, unit: WeightUnit?) {
        if let workingWeight = progressionExercise.workingWeight {
            return (workingWeight, progressionExercise.workingWeightUnit)
        }

        if let rep = historyRepository.mostRecentRep(for: exercise) {
            return (rep.weight, rep.weightUnit)
        }

        return (nil, nil)
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
            let low = progressionExercise.targetRepsLow ?? progressionExercise.targetReps ?? 8
            let high = progressionExercise.targetRepsHigh ?? progressionExercise.targetReps ?? max(low, 10)
            let current = progressionExercise.targetReps ?? low

            if current < high {
                progressionExercise.targetReps = current + 1
            } else {
                applyWeightIncrement(
                    progressionExercise: progressionExercise,
                    profile: profile,
                    actualWeight: actualWeight
                )
                progressionExercise.targetReps = low
            }
            progressionExercise.successCount = 0

        case .volume:
            progressionExercise.successCount += 1
            if progressionExercise.successCount >= resolvedThreshold {
                progressionExercise.targetSetCount += max(profile?.setIncrement ?? 1, 1)
                progressionExercise.successCount = 0
            }
        }
    }

    private func applyWeightIncrement(
        progressionExercise: ProgressionExercise,
        profile: ProgressionProfile?,
        actualWeight: (weight: Double, unit: WeightUnit)?
    ) {
        let unit = actualWeight?.unit ?? progressionExercise.workingWeightUnit
        let baseWeight = progressionExercise.workingWeight ?? actualWeight?.weight
        let incrementSourceUnit = profile?.incrementUnit ?? unit
        let incrementValue = (profile?.incrementValue ?? 0) * incrementSourceUnit.conversion(to: unit)

        progressionExercise.workingWeightUnit = unit
        if let baseWeight {
            progressionExercise.workingWeight = max(baseWeight + incrementValue, 0)
        }
    }
}
