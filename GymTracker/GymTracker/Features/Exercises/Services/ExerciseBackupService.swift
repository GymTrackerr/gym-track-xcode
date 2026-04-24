import Foundation
import SwiftData

@MainActor
final class ExerciseBackupService {
    enum BackupError: LocalizedError {
        case missingUser
        case invalidSchemaVersion(Int)
        case invalidBackup(String)
        case persistence(String)

        var errorDescription: String? {
            switch self {
            case .missingUser:
                return "You must be signed in to use exercise backup."
            case .invalidSchemaVersion(let version):
                return "Unsupported exercise backup schema version: \(version)."
            case .invalidBackup(let message):
                return message
            case .persistence(let message):
                return message
            }
        }
    }

    enum ImportMode: String {
        case merge
        case replace
    }

    struct ModelImportCounts {
        var inserted: Int = 0
        var updated: Int = 0
        var skipped: Int = 0
    }

    struct ImportReport {
        var exercises = ModelImportCounts()
        var routines = ModelImportCounts()
        var splitDays = ModelImportCounts()
        var programs = ModelImportCounts()
        var programBlocks = ModelImportCounts()
        var programWorkouts = ModelImportCounts()
        var progressionProfiles = ModelImportCounts()
        var progressionExercises = ModelImportCounts()
        var sessions = ModelImportCounts()
        var sessionEntries = ModelImportCounts()
        var sessionSets = ModelImportCounts()
        var sessionReps = ModelImportCounts()
        var warnings: [String] = []
    }

    private let modelContext: ModelContext
    private let currentUserProvider: () -> User?

    init(context: ModelContext, currentUserProvider: @escaping () -> User?) {
        self.modelContext = context
        self.currentUserProvider = currentUserProvider
    }

    // MARK: - Export

    // MARK: - Export

    func exportExercisesJSON() throws -> URL {
        guard let currentUser = currentUserProvider() else {
            throw BackupError.missingUser
        }
        let userId = currentUser.id

        let allExercises = try fetchExercises(userId: userId)
        let exportableExercises = allExercises.filter(\.isUserCreated)
        let npExerciseExports = allExercises.compactMap { exercise -> NpExerciseExportDTO? in
            guard !exercise.isUserCreated,
                  let npId = normalizedNpId(exercise.npId) else { return nil }
            return NpExerciseExportDTO(
                npId: npId,
                exerciseAliases: (exercise.aliases ?? [])
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        }

        let routines = try fetchRoutines(userId: userId)
        let routinesById = Dictionary(uniqueKeysWithValues: routines.map { ($0.id, $0) })
        let routineIds = Set(routines.map(\.id))

        let programs = try fetchPrograms(userId: userId)
        let programBlocks = programs
            .flatMap(\.blocks)
            .sorted { lhs, rhs in
                if lhs.program.id == rhs.program.id {
                    return lhs.order < rhs.order
                }
                return lhs.program.id.uuidString < rhs.program.id.uuidString
            }
        let programWorkouts = programBlocks
            .flatMap(\.workouts)
            .sorted { lhs, rhs in
                if lhs.programBlock.id == rhs.programBlock.id {
                    return lhs.order < rhs.order
                }
                return lhs.programBlock.id.uuidString < rhs.programBlock.id.uuidString
            }
        let visibleProgressionProfiles = try fetchAvailableProgressionProfiles(userId: userId)
        let progressionExercises = try fetchProgressionExercises(userId: userId)

        let allSplitDays = try modelContext.fetch(FetchDescriptor<ExerciseSplitDay>(sortBy: [SortDescriptor(\.order)]))
        let splitDaysForUser = allSplitDays.filter { routineIds.contains($0.routine.id) }

        let sessions = try fetchSessions(userId: userId)
        let sessionIds = Set(sessions.map(\.id))

        let allEntries = try modelContext.fetch(FetchDescriptor<SessionEntry>(sortBy: [SortDescriptor(\.order)]))
        let entriesForUser = allEntries.filter { sessionIds.contains($0.session.id) }
        let entryIds = Set(entriesForUser.map(\.id))

        let allSets = try modelContext.fetch(FetchDescriptor<SessionSet>(sortBy: [SortDescriptor(\.order)]))
        let setsForUser = allSets.filter { entryIds.contains($0.sessionEntry.id) }
        let setIds = Set(setsForUser.map(\.id))

        let allReps = try modelContext.fetch(FetchDescriptor<SessionRep>())
        let repsForUser = allReps.filter { setIds.contains($0.sessionSet.id) }

        var skippedSplitDays = 0
        var skippedEntries = 0
        var skippedSets = 0
        var skippedReps = 0

        let splitDayDTOs: [ExerciseSplitDayBackupDTO] = splitDaysForUser.compactMap { splitDay in
            let exerciseId = splitDay.exercise.id.uuidString
            let exerciseNpId = splitDay.exercise.npId
            if exerciseId.isEmpty && (exerciseNpId?.isEmpty ?? true) {
                skippedSplitDays += 1
                return nil
            }
            return ExerciseSplitDayBackupDTO(
                id: splitDay.id.uuidString,
                order: splitDay.order,
                routineId: splitDay.routine.id.uuidString,
                exerciseId: exerciseId,
                exerciseNpId: exerciseNpId
            )
        }

        let entryDTOs: [SessionEntryBackupDTO] = entriesForUser.compactMap { entry in
            let exerciseId = entry.exercise.id.uuidString
            let exerciseNpId = entry.exercise.npId
            if exerciseId.isEmpty && (exerciseNpId?.isEmpty ?? true) {
                skippedEntries += 1
                return nil
            }
            return SessionEntryBackupDTO(
                id: entry.id.uuidString,
                order: entry.order,
                isCompleted: entry.isCompleted,
                sessionId: entry.session.id.uuidString,
                exerciseId: exerciseId,
                exerciseNpId: exerciseNpId,
                appliedProgressionProfileId: entry.appliedProgressionProfileId?.uuidString,
                appliedProgressionNameSnapshot: entry.appliedProgressionNameSnapshot,
                appliedProgressionMiniDescriptionSnapshot: entry.appliedProgressionMiniDescriptionSnapshot,
                appliedProgressionTypeRaw: entry.appliedProgressionTypeRaw,
                appliedTargetSetCount: entry.appliedTargetSetCount,
                appliedTargetReps: entry.appliedTargetReps,
                appliedTargetRepsLow: entry.appliedTargetRepsLow,
                appliedTargetRepsHigh: entry.appliedTargetRepsHigh,
                appliedTargetWeight: entry.appliedTargetWeight,
                appliedTargetWeightLow: entry.appliedTargetWeightLow,
                appliedTargetWeightHigh: entry.appliedTargetWeightHigh,
                appliedTargetWeightUnitRaw: entry.appliedTargetWeightUnitRaw,
                appliedProgressionCycleSummary: entry.appliedProgressionCycleSummary
            )
        }
        let exportedEntryIds = Set(entryDTOs.compactMap { UUID(uuidString: $0.id) })

        let setDTOs: [SessionSetBackupDTO] = setsForUser.compactMap { sessionSet in
            guard exportedEntryIds.contains(sessionSet.sessionEntry.id) else {
                skippedSets += 1
                return nil
            }
            return SessionSetBackupDTO(
                id: sessionSet.id.uuidString,
                order: sessionSet.order,
                notes: sessionSet.notes,
                timestamp: sessionSet.timestamp,
                isCompleted: sessionSet.isCompleted,
                isDropSet: sessionSet.isDropSet,
                sessionEntryId: sessionSet.sessionEntry.id.uuidString,
                durationSeconds: sessionSet.durationSeconds,
                distance: sessionSet.distance,
                paceSeconds: sessionSet.paceSeconds,
                distanceUnitRaw: sessionSet.distanceUnitRaw,
                restSeconds: sessionSet.restSeconds
            )
        }
        let exportedSetIds = Set(setDTOs.compactMap { UUID(uuidString: $0.id) })

        let repDTOs: [SessionRepBackupDTO] = repsForUser.compactMap { rep in
            guard exportedSetIds.contains(rep.sessionSet.id) else {
                skippedReps += 1
                return nil
            }
            return SessionRepBackupDTO(
                id: rep.id.uuidString,
                weight: rep.weight,
                weightUnitRaw: rep.weight_unit,
                count: rep.count,
                notes: rep.notes,
                sessionSetId: rep.sessionSet.id.uuidString,
                baseWeight: rep.baseWeight,
                perSideWeight: rep.perSideWeight,
                isPerSide: rep.isPerSide
            )
        }

        let routineDTOs = routines.map {
            let splitSnapshot = $0.exerciseSplits
                .sorted { lhs, rhs in
                    if lhs.order != rhs.order { return lhs.order < rhs.order }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                .map { splitDay in
                    RoutineSplitDaySnapshotDTO(
                        id: splitDay.id.uuidString,
                        order: splitDay.order,
                        exerciseId: splitDay.exercise.id.uuidString,
                        exerciseNpId: splitDay.exercise.npId
                    )
                }
            return RoutineBackupDTO(
                id: $0.id.uuidString,
                userId: $0.user_id.uuidString,
                order: $0.order,
                name: $0.name,
                timestamp: $0.timestamp,
                isArchived: $0.isArchived,
                aliases: $0.aliases,
                defaultProgressionProfileId: $0.defaultProgressionProfileId?.uuidString,
                defaultProgressionProfileNameSnapshot: $0.defaultProgressionProfileNameSnapshot,
                splitDaySnapshot: splitSnapshot
            )
        }

        let programDTOs = programs.map {
            ProgramBackupDTO(
                id: $0.id.uuidString,
                userId: $0.user_id.uuidString,
                name: $0.name,
                notes: $0.notes,
                defaultProgressionProfileId: $0.defaultProgressionProfileId?.uuidString,
                defaultProgressionProfileNameSnapshot: $0.defaultProgressionProfileNameSnapshot,
                modeRaw: $0.modeRaw,
                startDate: $0.startDate,
                trainDaysBeforeRest: $0.trainDaysBeforeRest,
                restDays: $0.restDays,
                isActive: $0.isActive,
                isArchived: $0.isArchived,
                timestamp: $0.timestamp,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }

        let programBlockDTOs = programBlocks.map {
            ProgramBlockBackupDTO(
                id: $0.id.uuidString,
                order: $0.order,
                name: $0.name,
                durationCount: $0.durationCount,
                programId: $0.program.id.uuidString
            )
        }

        let programWorkoutDTOs = programWorkouts.map {
            ProgramWorkoutBackupDTO(
                id: $0.id.uuidString,
                order: $0.order,
                name: $0.name,
                weekdayIndex: $0.weekdayIndex,
                routineNameSnapshot: $0.routineNameSnapshot,
                programBlockId: $0.programBlock.id.uuidString,
                routineId: $0.routine?.id.uuidString
            )
        }

        let progressionProfileDTOs = visibleProgressionProfiles.map {
            ProgressionProfileBackupDTO(
                id: $0.id.uuidString,
                userId: $0.user_id?.uuidString,
                name: $0.name,
                miniDescription: $0.miniDescription,
                typeRaw: $0.typeRaw,
                incrementValue: $0.incrementValue,
                percentageIncreaseStored: $0.percentageIncreaseStored,
                incrementUnitRaw: $0.incrementUnitRaw,
                setIncrement: $0.setIncrement,
                successThreshold: $0.successThreshold,
                defaultSetsTarget: $0.defaultSetsTarget,
                defaultRepsTarget: $0.defaultRepsTarget,
                defaultRepsLow: $0.defaultRepsLow,
                defaultRepsHigh: $0.defaultRepsHigh,
                isBuiltIn: $0.isBuiltIn,
                isArchived: $0.isArchived,
                timestamp: $0.timestamp,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }

        let progressionExerciseDTOs = progressionExercises.map {
            ProgressionExerciseBackupDTO(
                id: $0.id.uuidString,
                userId: $0.user_id.uuidString,
                exerciseId: $0.exerciseId.uuidString,
                exerciseNameSnapshot: $0.exerciseNameSnapshot,
                progressionProfileId: $0.progressionProfileId?.uuidString,
                progressionNameSnapshot: $0.progressionNameSnapshot,
                progressionMiniDescriptionSnapshot: $0.progressionMiniDescriptionSnapshot,
                progressionTypeRaw: $0.progressionTypeRaw,
                assignmentSourceRaw: $0.assignmentSourceRaw,
                targetSetCount: $0.targetSetCount,
                targetReps: $0.targetReps,
                targetRepsLow: $0.targetRepsLow,
                targetRepsHigh: $0.targetRepsHigh,
                workingWeight: $0.workingWeight,
                suggestedWeightLow: $0.suggestedWeightLow,
                suggestedWeightHigh: $0.suggestedWeightHigh,
                workingWeightUnitRaw: $0.workingWeightUnitRaw,
                lastCompletedCycleWeight: $0.lastCompletedCycleWeight,
                lastCompletedCycleReps: $0.lastCompletedCycleReps,
                lastCompletedCycleUnitRaw: $0.lastCompletedCycleUnitRaw,
                successCount: $0.successCount,
                hasBackfilled: $0.hasBackfilled,
                backfilledAt: $0.backfilledAt,
                lastEvaluatedSessionId: $0.lastEvaluatedSessionId?.uuidString,
                timestamp: $0.timestamp,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }

        let sessionDTOs = sessions.map {
            SessionBackupDTO(
                id: $0.id.uuidString,
                userId: $0.user_id.uuidString,
                timestamp: $0.timestamp,
                timestampDone: $0.timestampDone,
                notes: $0.notes,
                routineId: $0.routine.map { routinesById[$0.id] != nil ? $0.id.uuidString : nil } ?? nil,
                programId: $0.program?.id.uuidString,
                programBlockId: $0.programBlockId?.uuidString,
                programBlockName: $0.programBlockName,
                programWorkoutId: $0.programWorkoutId?.uuidString,
                programWorkoutName: $0.programWorkoutName,
                programWeekIndex: $0.programWeekIndex,
                programSplitIndex: $0.programSplitIndex,
                importHash: $0.importHash
            )
        }

        let payload = ExerciseBackupRootDTO(
            schemaVersion: 2,
            exportedAt: Date(),
            userId: userId.uuidString,
            payload: ExercisePayloadDTO(
                exercises: exportableExercises.map(ExerciseBackupDTO.init),
                npExerciseExports: npExerciseExports.isEmpty ? nil : npExerciseExports,
                globalProgressionEnabled: currentUser.globalProgressionEnabled,
                globalDefaultProgressionProfileId: currentUser.defaultProgressionProfileId?.uuidString,
                onboardingGoalsRaw: currentUser.onboardingGoalsRaw,
                trainingExperienceRaw: currentUser.trainingExperienceRaw,
                routines: routineDTOs,
                programs: programDTOs,
                programBlocks: programBlockDTOs,
                programWorkouts: programWorkoutDTOs,
                progressionProfiles: progressionProfileDTOs,
                progressionExercises: progressionExerciseDTOs,
                splitDays: splitDayDTOs,
                sessions: sessionDTOs,
                sessionEntries: entryDTOs,
                sessionSets: setDTOs,
                sessionReps: repDTOs
            ),
            exportWarnings: warningMessages(
                skippedSplitDays: skippedSplitDays,
                skippedEntries: skippedEntries,
                skippedSets: skippedSets,
                skippedReps: skippedReps
            )
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(payload)
            let fileURL = backupURL()
            try data.write(to: fileURL, options: Data.WritingOptions.atomic)
            return fileURL
        } catch {
            throw BackupError.persistence("Could not write exercise backup file.")
        }
    }

    // MARK: - Import

    func importExercisesJSON(from url: URL, mode: ImportMode) throws -> ImportReport {
        let data = try readBackupData(from: url)
        return try importExercises(data: data, mode: mode)
    }

    func importExercises(data: Data, mode: ImportMode) throws -> ImportReport {
        guard let userId = currentUserProvider()?.id else {
            throw BackupError.missingUser
        }

        let root = try decodeBackupRoot(from: data)

        guard root.schemaVersion == 1 || root.schemaVersion == 2 else {
            throw BackupError.invalidSchemaVersion(root.schemaVersion)
        }

        // Preflight: validate references against current-user records plus incoming payload.
        let existingExercisesForUser = try fetchExercises(userId: userId)
        let preflightPlan = buildPreflightPlan(payload: root.payload, existingExercises: existingExercisesForUser)
        debugAssertPayloadReferenceScenario(payload: root.payload, plan: preflightPlan)
        guard preflightPlan.missingReferences.isEmpty else {
            let joined = preflightPlan.missingReferences.sorted().joined(separator: ", ")
            throw BackupError.invalidBackup("Missing exercise references: \(joined)")
        }

        if mode == .replace {
            try deleteExerciseDataForCurrentUser(userId: userId)
        }

        var report = ImportReport()
        report.warnings = root.exportWarnings ?? []

        // Refresh lookups after potential replace delete.
        var exerciseMaps = try buildCurrentExerciseMaps(userId: userId)

        // Upsert exercises from payload first so subsequent references can link locally.
        for dto in root.payload.exercises {
            let exerciseId = try uuid(from: dto.id, label: "exercise.id")
            _ = try uuid(from: dto.userId, label: "exercise.userId")

            let existingByNpId: Exercise?
            if let key = normalizedNpId(dto.npId) {
                existingByNpId = preferredExercise(from: exerciseMaps.byNpId[key], label: "npId=\(key)")
            } else {
                existingByNpId = nil
            }
            let existingById = preferredExercise(from: exerciseMaps.byId[exerciseId], label: "id=\(exerciseId.uuidString)")

            let target: Exercise
            if let existingByNpId {
                target = existingByNpId
                report.exercises.updated += 1
            } else if let existingById {
                target = existingById
                report.exercises.updated += 1
            } else {
                let resolvedType = resolveExerciseType(for: dto)
                target = Exercise(
                    name: dto.name,
                    type: resolvedType,
                    user_id: userId,
                    isUserCreated: dto.isUserCreated
                )
                target.id = exerciseId
                modelContext.insert(target)
                report.exercises.inserted += 1
            }

            target.id = exerciseId
            target.user_id = userId
            target.npId = dto.npId
            target.name = dto.name
            target.aliases = dto.aliases
            target.type = resolveExerciseType(for: dto).rawValue
            target.primary_muscles = dto.primaryMuscles
            target.secondary_muscles = dto.secondaryMuscles
            target.equipment = dto.equipment
            target.category = dto.category
            target.instructions = dto.instructions
            target.images = dto.images
            target.cachedMedia = dto.cachedMedia
            target.isUserCreated = dto.isUserCreated
            target.isArchived = dto.isArchived ?? false
            target.timestamp = dto.timestamp

            register(target, inById: &exerciseMaps.byId, byNpId: &exerciseMaps.byNpId)
            if let key = normalizedNpId(dto.npId) {
                exerciseMaps.byNpId[key] = dedupeExerciseList(exerciseMaps.byNpId[key], preferred: target)
            }
        }

        for npExport in root.payload.npExerciseExports ?? [] {
            guard let key = normalizedNpId(npExport.npId) else { continue }

            let incomingAliases = npExport.exerciseAliases
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if incomingAliases.isEmpty { continue }

            if let resolved = preferredExercise(from: exerciseMaps.byNpId[key], label: "npId=\(key)") {
                resolved.aliases = mergeAliasesCaseInsensitive(existing: resolved.aliases ?? [], incoming: incomingAliases)
                continue
            }

            // Preserve npId alias joins even when the underlying NP exercise doesn't yet exist.
            let placeholder = Exercise(
                name: "Imported NP Exercise (\(key))",
                type: .weight,
                user_id: userId,
                isUserCreated: false
            )
            placeholder.npId = key
            placeholder.aliases = mergeAliasesCaseInsensitive(existing: placeholder.aliases ?? [], incoming: incomingAliases)
            modelContext.insert(placeholder)
            register(placeholder, inById: &exerciseMaps.byId, byNpId: &exerciseMaps.byNpId)
            report.warnings.append("Created placeholder non-user exercise for npId=\(key) to preserve imported aliases.")
        }

        let existingProgressionProfiles = try fetchAvailableProgressionProfiles(userId: userId)
        var progressionProfilesById = Dictionary(uniqueKeysWithValues: existingProgressionProfiles.map { ($0.id, $0) })

        for dto in root.payload.progressionProfiles {
            let profileId = try uuid(from: dto.id, label: "progressionProfile.id")

            let profile: ProgressionProfile
            if let existing = progressionProfilesById[profileId] {
                profile = existing
                report.progressionProfiles.updated += 1
            } else {
                profile = ProgressionProfile(
                    userId: dto.userId == nil ? nil : userId,
                    name: dto.name,
                    miniDescription: dto.miniDescription,
                    type: ProgressionType(rawValue: dto.typeRaw) ?? .linear,
                    incrementValue: dto.incrementValue,
                    percentageIncrease: dto.percentageIncreaseStored ?? 0,
                    incrementUnit: WeightUnit(rawValue: dto.incrementUnitRaw) ?? .lb,
                    setIncrement: dto.setIncrement,
                    successThreshold: dto.successThreshold,
                    defaultSetsTarget: dto.defaultSetsTarget,
                    defaultRepsTarget: dto.defaultRepsTarget,
                    defaultRepsLow: dto.defaultRepsLow,
                    defaultRepsHigh: dto.defaultRepsHigh,
                    isBuiltIn: dto.isBuiltIn
                )
                profile.id = profileId
                modelContext.insert(profile)
                report.progressionProfiles.inserted += 1
            }

            profile.id = profileId
            profile.user_id = dto.userId == nil ? nil : userId
            profile.name = dto.name
            profile.miniDescription = dto.miniDescription
            profile.typeRaw = dto.typeRaw
            profile.incrementValue = dto.incrementValue
            profile.percentageIncreaseStored = dto.percentageIncreaseStored
            profile.incrementUnitRaw = dto.incrementUnitRaw
            profile.setIncrement = dto.setIncrement
            profile.successThreshold = dto.successThreshold
            profile.defaultSetsTarget = dto.defaultSetsTarget
            profile.defaultRepsTarget = dto.defaultRepsTarget
            profile.defaultRepsLow = dto.defaultRepsLow
            profile.defaultRepsHigh = dto.defaultRepsHigh
            profile.isBuiltIn = dto.isBuiltIn
            profile.isArchived = dto.isArchived ?? false
            profile.timestamp = dto.timestamp
            profile.createdAt = dto.createdAt
            profile.updatedAt = dto.updatedAt
            progressionProfilesById[profileId] = profile
        }

        if let currentUser = currentUserProvider(),
           (root.payload.globalProgressionEnabled != nil
                || root.payload.onboardingGoalsRaw != nil
                || root.payload.trainingExperienceRaw != nil) {
            if root.payload.globalProgressionEnabled != nil {
                currentUser.globalProgressionEnabled = root.payload.globalProgressionEnabled ?? false
                currentUser.defaultProgressionProfileId = root.payload.globalDefaultProgressionProfileId.flatMap { UUID(uuidString: $0) }
            }
            if let onboardingGoalsRaw = root.payload.onboardingGoalsRaw {
                currentUser.onboardingGoalsRaw = onboardingGoalsRaw
            }
            if root.payload.trainingExperienceRaw != nil {
                currentUser.trainingExperienceRaw = root.payload.trainingExperienceRaw
            }
            currentUser.updatedAt = Date()
        }

        let existingRoutines = try fetchRoutines(userId: userId)
        var routinesById = Dictionary(uniqueKeysWithValues: existingRoutines.map { ($0.id, $0) })

        for dto in root.payload.routines {
            let routineId = try uuid(from: dto.id, label: "routine.id")
            _ = try uuid(from: dto.userId, label: "routine.userId")

            let routine: Routine
            if let existing = routinesById[routineId] {
                routine = existing
                report.routines.updated += 1
            } else {
                routine = Routine(order: dto.order, name: dto.name, user_id: userId)
                routine.id = routineId
                modelContext.insert(routine)
                report.routines.inserted += 1
            }

            routine.id = routineId
            routine.user_id = userId
            routine.order = dto.order
            routine.name = dto.name
            routine.timestamp = dto.timestamp
            routine.isArchived = dto.isArchived ?? false
            routine.aliases = dto.aliases ?? []
            routine.defaultProgressionProfileId = dto.defaultProgressionProfileId.flatMap { UUID(uuidString: $0) }
            routine.defaultProgressionProfileNameSnapshot = dto.defaultProgressionProfileNameSnapshot
            routinesById[routineId] = routine
        }

        let authoritativeRoutineSplitSnapshots = root.payload.routines.reduce(into: [UUID: [RoutineSplitDaySnapshotDTO]]()) { result, dto in
            guard let snapshot = dto.splitDaySnapshot,
                  let routineId = UUID(uuidString: dto.id) else { return }
            result[routineId] = snapshot
        }

        let existingPrograms = try fetchPrograms(userId: userId)
        var programsById = Dictionary(uniqueKeysWithValues: existingPrograms.map { ($0.id, $0) })

        for dto in root.payload.programs {
            let programId = try uuid(from: dto.id, label: "program.id")

            let program: Program
            if let existing = programsById[programId] {
                program = existing
                report.programs.updated += 1
            } else {
                program = Program(
                    userId: userId,
                    name: dto.name,
                    notes: dto.notes,
                    mode: ProgramMode(rawValue: dto.modeRaw) ?? .weekly,
                    startDate: dto.startDate,
                    trainDaysBeforeRest: dto.trainDaysBeforeRest,
                    restDays: dto.restDays
                )
                program.id = programId
                modelContext.insert(program)
                report.programs.inserted += 1
            }

            program.id = programId
            program.user_id = userId
            program.name = dto.name
            program.notes = dto.notes
            program.defaultProgressionProfileId = dto.defaultProgressionProfileId.flatMap { UUID(uuidString: $0) }
            program.defaultProgressionProfileNameSnapshot = dto.defaultProgressionProfileNameSnapshot
            program.modeRaw = dto.modeRaw
            program.startDate = dto.startDate
            program.trainDaysBeforeRest = dto.trainDaysBeforeRest
            program.restDays = dto.restDays
            program.isActive = dto.isActive
            program.isArchived = dto.isArchived ?? false
            program.timestamp = dto.timestamp
            program.createdAt = dto.createdAt
            program.updatedAt = dto.updatedAt
            programsById[programId] = program
        }

        let existingProgramBlocks = programsById.values
            .flatMap(\.blocks)
        var programBlocksById = Dictionary(uniqueKeysWithValues: existingProgramBlocks.map { ($0.id, $0) })

        for dto in root.payload.programBlocks {
            let blockId = try uuid(from: dto.id, label: "programBlock.id")
            let programId = try uuid(from: dto.programId, label: "programBlock.programId")
            guard let program = programsById[programId] else {
                report.programBlocks.skipped += 1
                report.warnings.append("Skipped program block \(dto.id) because its program was missing.")
                continue
            }

            let block: ProgramBlock
            if let existing = programBlocksById[blockId] {
                block = existing
                report.programBlocks.updated += 1
            } else {
                block = ProgramBlock(order: dto.order, program: program, name: dto.name, durationCount: dto.durationCount)
                block.id = blockId
                modelContext.insert(block)
                report.programBlocks.inserted += 1
            }

            block.id = blockId
            block.order = dto.order
            block.name = dto.name
            block.durationCount = dto.durationCount
            block.program = program
            if !program.blocks.contains(where: { $0.id == block.id }) {
                program.blocks.append(block)
            }
            programBlocksById[blockId] = block
        }

        let existingProgramWorkouts = programBlocksById.values
            .flatMap(\.workouts)
        var programWorkoutsById = Dictionary(uniqueKeysWithValues: existingProgramWorkouts.map { ($0.id, $0) })

        for dto in root.payload.programWorkouts {
            let workoutId = try uuid(from: dto.id, label: "programWorkout.id")
            let blockId = try uuid(from: dto.programBlockId, label: "programWorkout.programBlockId")
            guard let block = programBlocksById[blockId] else {
                report.programWorkouts.skipped += 1
                report.warnings.append("Skipped program workout \(dto.id) because its block was missing.")
                continue
            }

            let routine = dto.routineId
                .flatMap { UUID(uuidString: $0) }
                .flatMap { routinesById[$0] }
            if dto.routineId != nil && routine == nil {
                report.warnings.append("Imported program workout \(dto.id) without its routine link because the routine was missing.")
            }

            let workout: ProgramWorkout
            if let existing = programWorkoutsById[workoutId] {
                workout = existing
                report.programWorkouts.updated += 1
            } else {
                workout = ProgramWorkout(
                    order: dto.order,
                    programBlock: block,
                    routine: routine,
                    name: dto.name,
                    weekdayIndex: dto.weekdayIndex
                )
                workout.id = workoutId
                modelContext.insert(workout)
                report.programWorkouts.inserted += 1
            }

            workout.id = workoutId
            workout.order = dto.order
            workout.name = dto.name
            workout.weekdayIndex = dto.weekdayIndex
            workout.routineNameSnapshot = dto.routineNameSnapshot
            workout.routineIdSnapshot = dto.routineId.flatMap { UUID(uuidString: $0) }
            workout.programBlock = block
            workout.updateRoutineLink(routine)
            if !block.workouts.contains(where: { $0.id == workout.id }) {
                block.workouts.append(workout)
            }
            programWorkoutsById[workoutId] = workout
        }

        let existingSessions = try fetchSessions(userId: userId)
        var sessionsById = Dictionary(uniqueKeysWithValues: existingSessions.map { ($0.id, $0) })

        for dto in root.payload.sessions {
            let sessionId = try uuid(from: dto.id, label: "session.id")
            _ = try uuid(from: dto.userId, label: "session.userId")

            let routine: Routine?
            if let routineIdString = dto.routineId {
                let routineId = try uuid(from: routineIdString, label: "session.routineId")
                if let linkedRoutine = routinesById[routineId] {
                    routine = linkedRoutine
                } else {
                    routine = nil
                    report.warnings.append("Imported session \(dto.id) without its routine link because the routine was missing.")
                }
            } else {
                routine = nil
            }

            let program: Program?
            if let programIdString = dto.programId {
                let programId = try uuid(from: programIdString, label: "session.programId")
                if let linkedProgram = programsById[programId] {
                    program = linkedProgram
                } else {
                    program = nil
                    report.warnings.append("Imported session \(dto.id) without its program link because the program was missing.")
                }
            } else {
                program = nil
            }

            let session: Session
            if let existing = sessionsById[sessionId] {
                session = existing
                report.sessions.updated += 1
            } else {
                session = Session(timestamp: dto.timestamp, user_id: userId, routine: routine, notes: dto.notes, program: program)
                session.id = sessionId
                modelContext.insert(session)
                report.sessions.inserted += 1
            }

            session.id = sessionId
            session.user_id = userId
            session.timestamp = dto.timestamp
            session.timestampDone = dto.timestampDone
            session.notes = dto.notes
            session.routine = routine
            session.program = program
            session.programBlockId = dto.programBlockId.flatMap { UUID(uuidString: $0) }
            session.programBlockName = dto.programBlockName
            session.programWorkoutId = dto.programWorkoutId.flatMap { UUID(uuidString: $0) }
            session.programWorkoutName = dto.programWorkoutName
            session.programWeekIndex = dto.programWeekIndex
            session.programSplitIndex = dto.programSplitIndex
            session.importHash = dto.importHash
            sessionsById[sessionId] = session
        }

        let allEntries = try modelContext.fetch(FetchDescriptor<SessionEntry>())
        var entriesById = Dictionary(uniqueKeysWithValues: allEntries.filter { $0.session.user_id == userId }.map { ($0.id, $0) })

        for dto in root.payload.sessionEntries {
            let entryId = try uuid(from: dto.id, label: "sessionEntry.id")
            let sessionId = try uuid(from: dto.sessionId, label: "sessionEntry.sessionId")
            guard let session = sessionsById[sessionId] else {
                throw BackupError.invalidBackup("Session entry \(dto.id) references missing session.")
            }

            let exercise = try resolveExercise(
                exerciseIdString: dto.exerciseId,
                exerciseNpId: dto.exerciseNpId,
                exercisesById: exerciseMaps.byId,
                exercisesByNpId: exerciseMaps.byNpId
            )

            let entry: SessionEntry
            if let existing = entriesById[entryId] {
                entry = existing
                report.sessionEntries.updated += 1
            } else {
                entry = SessionEntry(order: dto.order, session: session, exercise: exercise)
                entry.id = entryId
                modelContext.insert(entry)
                report.sessionEntries.inserted += 1
            }

            entry.id = entryId
            entry.order = dto.order
            entry.isCompleted = dto.isCompleted
            entry.session = session
            entry.exercise = exercise
            entry.appliedProgressionProfileId = dto.appliedProgressionProfileId.flatMap { UUID(uuidString: $0) }
            entry.appliedProgressionNameSnapshot = dto.appliedProgressionNameSnapshot
            entry.appliedProgressionMiniDescriptionSnapshot = dto.appliedProgressionMiniDescriptionSnapshot
            entry.appliedProgressionTypeRaw = dto.appliedProgressionTypeRaw
            entry.appliedTargetSetCount = dto.appliedTargetSetCount
            entry.appliedTargetReps = dto.appliedTargetReps
            entry.appliedTargetRepsLow = dto.appliedTargetRepsLow
            entry.appliedTargetRepsHigh = dto.appliedTargetRepsHigh
            entry.appliedTargetWeight = dto.appliedTargetWeight
            entry.appliedTargetWeightLow = dto.appliedTargetWeightLow
            entry.appliedTargetWeightHigh = dto.appliedTargetWeightHigh
            entry.appliedTargetWeightUnitRaw = dto.appliedTargetWeightUnitRaw
            entry.appliedProgressionCycleSummary = dto.appliedProgressionCycleSummary
            if !session.sessionEntries.contains(where: { $0.id == entry.id }) {
                session.sessionEntries.append(entry)
            }
            entriesById[entryId] = entry
        }

        let existingProgressionExercises = try fetchProgressionExercises(userId: userId)
        var progressionExercisesById = Dictionary(uniqueKeysWithValues: existingProgressionExercises.map { ($0.id, $0) })
        var progressionExercisesByExerciseId = Dictionary(uniqueKeysWithValues: existingProgressionExercises.map { ($0.exerciseId, $0) })

        for dto in root.payload.progressionExercises {
            let progressionExerciseId = try uuid(from: dto.id, label: "progressionExercise.id")
            let exerciseId = try uuid(from: dto.exerciseId, label: "progressionExercise.exerciseId")
            guard let exercise = preferredExercise(from: exerciseMaps.byId[exerciseId], label: "id=\(exerciseId.uuidString)") else {
                report.progressionExercises.skipped += 1
                report.warnings.append("Skipped progression state \(dto.id) because its exercise was missing.")
                continue
            }

            let progressionExercise: ProgressionExercise
            if let existing = progressionExercisesById[progressionExerciseId] ?? progressionExercisesByExerciseId[exerciseId] {
                progressionExercise = existing
                report.progressionExercises.updated += 1
            } else {
                progressionExercise = ProgressionExercise(
                    userId: userId,
                    exerciseId: exercise.id,
                    exerciseName: dto.exerciseNameSnapshot,
                    profile: dto.progressionProfileId
                        .flatMap { UUID(uuidString: $0) }
                        .flatMap { progressionProfilesById[$0] },
                    targetSetCount: dto.targetSetCount,
                    targetReps: dto.targetReps,
                    targetRepsLow: dto.targetRepsLow,
                    targetRepsHigh: dto.targetRepsHigh
                )
                progressionExercise.id = progressionExerciseId
                modelContext.insert(progressionExercise)
                report.progressionExercises.inserted += 1
            }

            progressionExercise.id = progressionExerciseId
            progressionExercise.user_id = userId
            progressionExercise.exerciseId = exercise.id
            progressionExercise.exerciseNameSnapshot = dto.exerciseNameSnapshot
            progressionExercise.progressionProfileId = dto.progressionProfileId.flatMap { UUID(uuidString: $0) }
            progressionExercise.progressionNameSnapshot = dto.progressionNameSnapshot
            progressionExercise.progressionMiniDescriptionSnapshot = dto.progressionMiniDescriptionSnapshot
            progressionExercise.progressionTypeRaw = dto.progressionTypeRaw
            progressionExercise.assignmentSourceRaw = dto.assignmentSourceRaw
            progressionExercise.targetSetCount = dto.targetSetCount
            progressionExercise.targetReps = dto.targetReps
            progressionExercise.targetRepsLow = dto.targetRepsLow
            progressionExercise.targetRepsHigh = dto.targetRepsHigh
            progressionExercise.workingWeight = dto.workingWeight
            progressionExercise.suggestedWeightLow = dto.suggestedWeightLow
            progressionExercise.suggestedWeightHigh = dto.suggestedWeightHigh
            progressionExercise.workingWeightUnitRaw = dto.workingWeightUnitRaw
            progressionExercise.lastCompletedCycleWeight = dto.lastCompletedCycleWeight
            progressionExercise.lastCompletedCycleReps = dto.lastCompletedCycleReps
            progressionExercise.lastCompletedCycleUnitRaw = dto.lastCompletedCycleUnitRaw
            progressionExercise.successCount = dto.successCount
            progressionExercise.hasBackfilled = dto.hasBackfilled
            progressionExercise.backfilledAt = dto.backfilledAt
            progressionExercise.lastEvaluatedSessionId = dto.lastEvaluatedSessionId.flatMap { UUID(uuidString: $0) }
            progressionExercise.timestamp = dto.timestamp
            progressionExercise.createdAt = dto.createdAt
            progressionExercise.updatedAt = dto.updatedAt
            progressionExercisesById[progressionExerciseId] = progressionExercise
            progressionExercisesByExerciseId[exercise.id] = progressionExercise
        }

        let allSets = try modelContext.fetch(FetchDescriptor<SessionSet>())
        var setsById = Dictionary(uniqueKeysWithValues: allSets.filter { $0.sessionEntry.session.user_id == userId }.map { ($0.id, $0) })

        for dto in root.payload.sessionSets {
            let setId = try uuid(from: dto.id, label: "sessionSet.id")
            let entryId = try uuid(from: dto.sessionEntryId, label: "sessionSet.sessionEntryId")
            guard let entry = entriesById[entryId] else {
                throw BackupError.invalidBackup("Session set \(dto.id) references missing session entry.")
            }

            let sessionSet: SessionSet
            if let existing = setsById[setId] {
                sessionSet = existing
                report.sessionSets.updated += 1
            } else {
                sessionSet = SessionSet(order: dto.order, sessionEntry: entry, notes: dto.notes)
                sessionSet.id = setId
                modelContext.insert(sessionSet)
                report.sessionSets.inserted += 1
            }

            sessionSet.id = setId
            sessionSet.order = dto.order
            sessionSet.notes = dto.notes
            sessionSet.timestamp = dto.timestamp
            sessionSet.isCompleted = dto.isCompleted
            sessionSet.isDropSet = dto.isDropSet
            sessionSet.durationSeconds = dto.durationSeconds
            sessionSet.distance = dto.distance
            sessionSet.paceSeconds = dto.paceSeconds
            sessionSet.distanceUnitRaw = dto.distanceUnitRaw
            sessionSet.restSeconds = dto.restSeconds
            sessionSet.sessionEntry = entry
            if !entry.sets.contains(where: { $0.id == sessionSet.id }) {
                entry.sets.append(sessionSet)
            }
            setsById[setId] = sessionSet
        }

        let allReps = try modelContext.fetch(FetchDescriptor<SessionRep>())
        var repsById = Dictionary(uniqueKeysWithValues: allReps.filter { $0.sessionSet.sessionEntry.session.user_id == userId }.map { ($0.id, $0) })

        for dto in root.payload.sessionReps {
            let repId = try uuid(from: dto.id, label: "sessionRep.id")
            let setId = try uuid(from: dto.sessionSetId, label: "sessionRep.sessionSetId")
            guard let sessionSet = setsById[setId] else {
                throw BackupError.invalidBackup("Session rep \(dto.id) references missing session set.")
            }

            let rep: SessionRep
            if let existing = repsById[repId] {
                rep = existing
                report.sessionReps.updated += 1
            } else {
                rep = SessionRep(
                    sessionSet: sessionSet,
                    weight: dto.weight,
                    weight_unit: WeightUnit(rawValue: dto.weightUnitRaw) ?? .lb,
                    count: dto.count,
                    notes: dto.notes
                )
                rep.id = repId
                modelContext.insert(rep)
                report.sessionReps.inserted += 1
            }

            rep.id = repId
            rep.weight = dto.weight
            rep.weight_unit = dto.weightUnitRaw
            rep.count = dto.count
            rep.notes = dto.notes
            rep.baseWeight = dto.baseWeight
            rep.perSideWeight = dto.perSideWeight
            rep.isPerSide = dto.isPerSide ?? false
            rep.sessionSet = sessionSet
            if !sessionSet.sessionReps.contains(where: { $0.id == rep.id }) {
                sessionSet.sessionReps.append(rep)
            }
            repsById[repId] = rep
        }

        let allSplitDays = try modelContext.fetch(FetchDescriptor<ExerciseSplitDay>())
        var splitDaysById = Dictionary(uniqueKeysWithValues: allSplitDays.filter { $0.routine.user_id == userId }.map { ($0.id, $0) })

        for (routineId, snapshot) in authoritativeRoutineSplitSnapshots {
            guard let routine = routinesById[routineId] else { continue }

            let snapshotIds = Set(snapshot.compactMap { UUID(uuidString: $0.id) })
            let staleSplitDays = routine.exerciseSplits.filter { !snapshotIds.contains($0.id) }
            if !staleSplitDays.isEmpty {
                routine.exerciseSplits.removeAll { splitDay in
                    staleSplitDays.contains(where: { $0.id == splitDay.id })
                }
                for splitDay in staleSplitDays {
                    splitDaysById.removeValue(forKey: splitDay.id)
                    modelContext.delete(splitDay)
                }
            }

            for splitDTO in snapshot {
                let splitDayId = try uuid(from: splitDTO.id, label: "routine.splitDaySnapshot.id")
                let exercise = try resolveExercise(
                    exerciseIdString: splitDTO.exerciseId,
                    exerciseNpId: splitDTO.exerciseNpId,
                    exercisesById: exerciseMaps.byId,
                    exercisesByNpId: exerciseMaps.byNpId
                )

                let splitDay: ExerciseSplitDay
                if let existing = splitDaysById[splitDayId] {
                    splitDay = existing
                    report.splitDays.updated += 1
                } else {
                    splitDay = ExerciseSplitDay(order: splitDTO.order, routine: routine, exercise: exercise)
                    splitDay.id = splitDayId
                    modelContext.insert(splitDay)
                    report.splitDays.inserted += 1
                }

                splitDay.id = splitDayId
                splitDay.order = splitDTO.order
                splitDay.routine = routine
                splitDay.exercise = exercise
                if !routine.exerciseSplits.contains(where: { $0.id == splitDay.id }) {
                    routine.exerciseSplits.append(splitDay)
                }
                splitDaysById[splitDayId] = splitDay
            }
        }

        for dto in root.payload.splitDays {
            let splitDayId = try uuid(from: dto.id, label: "splitDay.id")
            let routineId = try uuid(from: dto.routineId, label: "splitDay.routineId")
            if authoritativeRoutineSplitSnapshots[routineId] != nil {
                continue
            }
            guard let routine = routinesById[routineId] else {
                report.splitDays.skipped += 1
                report.warnings.append("Skipped split day \(dto.id) because its routine was missing.")
                continue
            }

            let exercise = try resolveExercise(
                exerciseIdString: dto.exerciseId,
                exerciseNpId: dto.exerciseNpId,
                exercisesById: exerciseMaps.byId,
                exercisesByNpId: exerciseMaps.byNpId
            )

            let splitDay: ExerciseSplitDay
            if let existing = splitDaysById[splitDayId] {
                splitDay = existing
                report.splitDays.updated += 1
            } else {
                splitDay = ExerciseSplitDay(order: dto.order, routine: routine, exercise: exercise)
                splitDay.id = splitDayId
                modelContext.insert(splitDay)
                report.splitDays.inserted += 1
            }

            splitDay.id = splitDayId
            splitDay.order = dto.order
            splitDay.routine = routine
            splitDay.exercise = exercise
            if !routine.exerciseSplits.contains(where: { $0.id == splitDay.id }) {
                routine.exerciseSplits.append(splitDay)
            }
            splitDaysById[splitDayId] = splitDay
        }

        do {
            try modelContext.save()
            return report
        } catch {
            throw BackupError.persistence("Could not import exercise backup.")
        }
    }

    // MARK: - Data Loading

    private func readBackupData(from url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw BackupError.persistence("Could not read exercise backup file.")
        }
    }

    private func decodeBackupRoot(from data: Data) throws -> ExerciseBackupRootDTO {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ExerciseBackupRootDTO.self, from: data)
        } catch {
            throw BackupError.invalidBackup("Exercise backup file format is invalid.")
        }
    }

    private func buildCurrentExerciseMaps(userId: UUID) throws -> ExerciseLookupMaps {
        let currentExercises = try fetchExercises(userId: userId)
        return ExerciseLookupMaps(
            byId: groupExercisesById(currentExercises),
            byNpId: groupExercisesByNpId(currentExercises)
        )
    }

    // MARK: - Queries

    private func fetchExercises(userId: UUID) throws -> [Exercise] {
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { item in
                item.user_id == userId
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchRoutines(userId: UUID) throws -> [Routine] {
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate<Routine> { item in
                item.user_id == userId
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchPrograms(userId: UUID) throws -> [Program] {
        let descriptor = FetchDescriptor<Program>(
            predicate: #Predicate<Program> { item in
                item.user_id == userId
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchAvailableProgressionProfiles(userId: UUID) throws -> [ProgressionProfile] {
        let descriptor = FetchDescriptor<ProgressionProfile>(
            predicate: #Predicate<ProgressionProfile> { item in
                item.soft_deleted == false && (item.user_id == nil || item.user_id == userId)
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchProgressionExercises(userId: UUID) throws -> [ProgressionExercise] {
        let descriptor = FetchDescriptor<ProgressionExercise>(
            predicate: #Predicate<ProgressionExercise> { item in
                item.user_id == userId && item.soft_deleted == false
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchSessions(userId: UUID) throws -> [Session] {
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate<Session> { item in
                item.user_id == userId
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Delete Helpers

    private func deleteExerciseDataForCurrentUser(userId: UUID) throws {
        let reps = try modelContext.fetch(FetchDescriptor<SessionRep>()).filter { $0.sessionSet.sessionEntry.session.user_id == userId }
        for rep in reps { modelContext.delete(rep) }

        let sets = try modelContext.fetch(FetchDescriptor<SessionSet>()).filter { $0.sessionEntry.session.user_id == userId }
        for sessionSet in sets { modelContext.delete(sessionSet) }

        let entries = try modelContext.fetch(FetchDescriptor<SessionEntry>()).filter { $0.session.user_id == userId }
        for entry in entries { modelContext.delete(entry) }

        let sessions = try fetchSessions(userId: userId)
        for session in sessions { modelContext.delete(session) }

        let splitDays = try modelContext.fetch(FetchDescriptor<ExerciseSplitDay>()).filter { $0.routine.user_id == userId }
        for splitDay in splitDays { modelContext.delete(splitDay) }

        let progressionExercises = try fetchProgressionExercises(userId: userId)
        for progressionExercise in progressionExercises { modelContext.delete(progressionExercise) }

        let programs = try fetchPrograms(userId: userId)
        for program in programs { modelContext.delete(program) }

        let routines = try fetchRoutines(userId: userId)
        for routine in routines { modelContext.delete(routine) }

        let progressionProfiles = try fetchAvailableProgressionProfiles(userId: userId).filter { $0.user_id == userId }
        for profile in progressionProfiles { modelContext.delete(profile) }
    }

    // MARK: - Warning Helpers

    private func warningMessages(
        skippedSplitDays: Int,
        skippedEntries: Int,
        skippedSets: Int,
        skippedReps: Int
    ) -> [String] {
        var warnings: [String] = []
        if skippedSplitDays > 0 {
            warnings.append("Skipped \(skippedSplitDays) split day records missing valid exercise link keys.")
        }
        if skippedEntries > 0 {
            warnings.append("Skipped \(skippedEntries) session entry records missing valid exercise link keys.")
        }
        if skippedSets > 0 {
            warnings.append("Skipped \(skippedSets) session set records because parent entries were skipped.")
        }
        if skippedReps > 0 {
            warnings.append("Skipped \(skippedReps) session rep records because parent sets were skipped.")
        }
        return warnings
    }

    // MARK: - Preflight

    private func buildPreflightPlan(payload: ExercisePayloadDTO, existingExercises: [Exercise]) -> ExercisePreflightPlan {
        var plan = ExercisePreflightPlan()

        let existingById = Set(existingExercises.map(\.id))
        let existingByNpId = Set(existingExercises.compactMap { normalizedNpId($0.npId) })
        let payloadById = Set(payload.exercises.compactMap { UUID(uuidString: $0.id) })
        let payloadByNpId = Set(payload.exercises.compactMap { normalizedNpId($0.npId) })

        for entry in payload.sessionEntries {
            classifyReference(
                exerciseIdString: entry.exerciseId,
                exerciseNpId: entry.exerciseNpId,
                existingById: existingById,
                existingByNpId: existingByNpId,
                payloadById: payloadById,
                payloadByNpId: payloadByNpId,
                plan: &plan
            )
        }

        for splitDay in payload.splitDays {
            classifyReference(
                exerciseIdString: splitDay.exerciseId,
                exerciseNpId: splitDay.exerciseNpId,
                existingById: existingById,
                existingByNpId: existingByNpId,
                payloadById: payloadById,
                payloadByNpId: payloadByNpId,
                plan: &plan
            )
        }

        for routine in payload.routines {
            for splitDay in routine.splitDaySnapshot ?? [] {
                classifyReference(
                    exerciseIdString: splitDay.exerciseId,
                    exerciseNpId: splitDay.exerciseNpId,
                    existingById: existingById,
                    existingByNpId: existingByNpId,
                    payloadById: payloadById,
                    payloadByNpId: payloadByNpId,
                    plan: &plan
                )
            }
        }

        return plan
    }

    private func classifyReference(
        exerciseIdString: String?,
        exerciseNpId: String?,
        existingById: Set<UUID>,
        existingByNpId: Set<String>,
        payloadById: Set<UUID>,
        payloadByNpId: Set<String>,
        plan: inout ExercisePreflightPlan
    ) {
        if let npIdKey = normalizedNpId(exerciseNpId) {
            if payloadByNpId.contains(npIdKey) {
                plan.createNpIds.insert(npIdKey)
                return
            }
            if existingByNpId.contains(npIdKey) {
                plan.linkNpIds.insert(npIdKey)
                return
            }
            plan.missingReferences.insert(referenceLabel(npId: exerciseNpId, id: exerciseIdString))
            return
        }

        let trimmedId = exerciseIdString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedId.isEmpty else {
            plan.missingReferences.insert(referenceLabel(npId: exerciseNpId, id: exerciseIdString))
            return
        }

        guard let exerciseId = UUID(uuidString: trimmedId) else {
            plan.missingReferences.insert(referenceLabel(npId: exerciseNpId, id: exerciseIdString))
            return
        }

        if payloadById.contains(exerciseId) {
            plan.createIds.insert(exerciseId)
            return
        }
        if existingById.contains(exerciseId) {
            plan.linkIds.insert(exerciseId)
            return
        }
        plan.missingReferences.insert(referenceLabel(npId: exerciseNpId, id: exerciseIdString))
    }

    // MARK: - Resolution

    private func referenceLabel(npId: String?, id: String?) -> String {
        let np = (npId?.isEmpty == false) ? "npId=\(npId!)" : "npId=nil"
        let sid = (id?.isEmpty == false) ? "id=\(id!)" : "id=nil"
        return "[\(np), \(sid)]"
    }

    private func resolveExercise(
        exerciseIdString: String?,
        exerciseNpId: String?,
        exercisesById: [UUID: [Exercise]],
        exercisesByNpId: [String: [Exercise]]
    ) throws -> Exercise {
        if let key = normalizedNpId(exerciseNpId) {
            if let exercise = preferredExercise(from: exercisesByNpId[key], label: "npId=\(key)") {
                return exercise
            }
            throw BackupError.invalidBackup("Missing exercise reference: npId=\(exerciseNpId ?? key)")
        }

        let trimmedExerciseId = exerciseIdString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedExerciseId.isEmpty else {
            throw BackupError.invalidBackup("Missing exercise reference: id=nil")
        }

        if let exerciseId = UUID(uuidString: trimmedExerciseId) {
            if let exercise = preferredExercise(from: exercisesById[exerciseId], label: "id=\(trimmedExerciseId)") {
                return exercise
            }
            throw BackupError.invalidBackup("Missing exercise reference: id=\(trimmedExerciseId)")
        }

        throw BackupError.invalidBackup("Invalid UUID exercise reference: id=\(trimmedExerciseId)")
    }

    // MARK: - Parsing & Map Building

    private func uuid(from value: String, label: String) throws -> UUID {
        guard let id = UUID(uuidString: value) else {
            throw BackupError.invalidBackup("Invalid UUID for \(label): \(value)")
        }
        return id
    }

    private func groupExercisesById(_ exercises: [Exercise]) -> [UUID: [Exercise]] {
        var grouped: [UUID: [Exercise]] = [:]
        for exercise in exercises {
            grouped[exercise.id, default: []].append(exercise)
        }
        return grouped
    }

    private func groupExercisesByNpId(_ exercises: [Exercise]) -> [String: [Exercise]] {
        var grouped: [String: [Exercise]] = [:]
        for exercise in exercises {
            guard let key = normalizedNpId(exercise.npId) else { continue }
            grouped[key, default: []].append(exercise)
        }
        return grouped
    }

    // MARK: - Lookup Helpers

    private func preferredExercise(from exercises: [Exercise]?, label: String) -> Exercise? {
        guard let exercises, !exercises.isEmpty else { return nil }
        if exercises.count > 1 {
            print("Ambiguous exercise match for \(label). Using safest deterministic selection.")
        }
        return exercises.max(by: { lhs, rhs in
            let lhsScore = lhs.sessionEntries.count + lhs.splits.count
            let rhsScore = rhs.sessionEntries.count + rhs.splits.count
            if lhsScore != rhsScore { return lhsScore < rhsScore }
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp > rhs.timestamp }
            return lhs.id.uuidString > rhs.id.uuidString
        })
    }

    private func dedupeExerciseList(_ exercises: [Exercise]?, preferred: Exercise) -> [Exercise] {
        var unique: [UUID: Exercise] = [preferred.id: preferred]
        for exercise in exercises ?? [] {
            unique[exercise.id] = exercise
        }
        unique[preferred.id] = preferred
        return Array(unique.values)
    }

    private func register(
        _ exercise: Exercise,
        inById byId: inout [UUID: [Exercise]],
        byNpId: inout [String: [Exercise]]
    ) {
        byId[exercise.id] = dedupeExerciseList(byId[exercise.id], preferred: exercise)
        if let key = normalizedNpId(exercise.npId) {
            byNpId[key] = dedupeExerciseList(byNpId[key], preferred: exercise)
        }
    }

    private func mergeAliasesCaseInsensitive(existing: [String], incoming: [String]) -> [String] {
        var ordered: [String] = []
        var seen: Set<String> = []

        for alias in existing + incoming {
            let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                ordered.append(trimmed)
            }
        }

        return ordered.sorted()
    }

    // MARK: - Debug Checks

    private func debugAssertPayloadReferenceScenario(payload: ExercisePayloadDTO, plan: ExercisePreflightPlan) {
#if DEBUG
        guard !payload.exercises.isEmpty else { return }
        let hasRoutineSplitSnapshots = payload.routines.contains { !($0.splitDaySnapshot ?? []).isEmpty }
        guard !payload.sessionEntries.isEmpty || !payload.splitDays.isEmpty || hasRoutineSplitSnapshots else { return }

        let payloadExerciseIds = Set(payload.exercises.compactMap { UUID(uuidString: $0.id) })
        let payloadExerciseNpIds = Set(payload.exercises.compactMap { normalizedNpId($0.npId) })

        let sessionReferencesPayload = payload.sessionEntries.contains { dto in
            if let key = normalizedNpId(dto.exerciseNpId), payloadExerciseNpIds.contains(key) {
                return true
            }
            if let idString = dto.exerciseId?.trimmingCharacters(in: .whitespacesAndNewlines),
               let id = UUID(uuidString: idString),
               payloadExerciseIds.contains(id) {
                return true
            }
            return false
        }
        let splitReferencesPayload = payload.splitDays.contains { dto in
            if let key = normalizedNpId(dto.exerciseNpId), payloadExerciseNpIds.contains(key) {
                return true
            }
            if let idString = dto.exerciseId?.trimmingCharacters(in: .whitespacesAndNewlines),
               let id = UUID(uuidString: idString),
               payloadExerciseIds.contains(id) {
                return true
            }
            return false
        }
        let routineSplitReferencesPayload = payload.routines.contains { routine in
            (routine.splitDaySnapshot ?? []).contains { dto in
                if let key = normalizedNpId(dto.exerciseNpId), payloadExerciseNpIds.contains(key) {
                    return true
                }
                if let idString = dto.exerciseId?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let id = UUID(uuidString: idString),
                   payloadExerciseIds.contains(id) {
                    return true
                }
                return false
            }
        }

        if sessionReferencesPayload || splitReferencesPayload || routineSplitReferencesPayload {
            assert(
                plan.missingReferences.isEmpty,
                "Preflight should allow payload-contained exercise references for entries/split days."
            )
        }
#endif
    }

    private func resolveExerciseType(for dto: ExerciseBackupDTO) -> ExerciseType {
        if let rawType = dto.type {
            return ExerciseType.fromPersisted(rawValue: rawType)
        }
        return ExerciseType.from(apiCategory: dto.category)
    }

    // MARK: - Normalization

    private func normalizedNpId(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }

    // MARK: - File Output

    private func backupURL() -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let fileName = "exercise-backup-\(stamp).json"

        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return documents.appendingPathComponent(fileName)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }
}

private struct ExerciseLookupMaps {
    var byId: [UUID: [Exercise]]
    var byNpId: [String: [Exercise]]
}

private struct ExercisePreflightPlan {
    var linkIds: Set<UUID> = []
    var linkNpIds: Set<String> = []
    var createIds: Set<UUID> = []
    var createNpIds: Set<String> = []
    var missingReferences: Set<String> = []
}

private struct ExerciseBackupRootDTO: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let userId: String
    let payload: ExercisePayloadDTO
    let exportWarnings: [String]?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case exportedAt
        case userId
        case payload
        case data
        case exportWarnings
    }

    init(
        schemaVersion: Int,
        exportedAt: Date,
        userId: String,
        payload: ExercisePayloadDTO,
        exportWarnings: [String]?
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.userId = userId
        self.payload = payload
        self.exportWarnings = exportWarnings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        userId = try container.decode(String.self, forKey: .userId)
        payload = try container.decodeIfPresent(ExercisePayloadDTO.self, forKey: .payload)
            ?? container.decodeIfPresent(ExercisePayloadDTO.self, forKey: .data)
            ?? ExercisePayloadDTO()
        exportWarnings = try container.decodeIfPresent([String].self, forKey: .exportWarnings)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(exportedAt, forKey: .exportedAt)
        try container.encode(userId, forKey: .userId)
        try container.encode(payload, forKey: .payload)
        try container.encodeIfPresent(exportWarnings, forKey: .exportWarnings)
    }
}

private struct ExercisePayloadDTO: Codable {
    let exercises: [ExerciseBackupDTO]
    let npExerciseExports: [NpExerciseExportDTO]?
    let globalProgressionEnabled: Bool?
    let globalDefaultProgressionProfileId: String?
    let onboardingGoalsRaw: [String]?
    let trainingExperienceRaw: String?
    let routines: [RoutineBackupDTO]
    let programs: [ProgramBackupDTO]
    let programBlocks: [ProgramBlockBackupDTO]
    let programWorkouts: [ProgramWorkoutBackupDTO]
    let progressionProfiles: [ProgressionProfileBackupDTO]
    let progressionExercises: [ProgressionExerciseBackupDTO]
    let splitDays: [ExerciseSplitDayBackupDTO]
    let sessions: [SessionBackupDTO]
    let sessionEntries: [SessionEntryBackupDTO]
    let sessionSets: [SessionSetBackupDTO]
    let sessionReps: [SessionRepBackupDTO]

    private enum CodingKeys: String, CodingKey {
        case exercises
        case npExerciseExports
        case globalProgressionEnabled
        case globalDefaultProgressionProfileId
        case onboardingGoalsRaw
        case trainingExperienceRaw
        case routines
        case programs
        case programBlocks
        case programWorkouts
        case progressionProfiles
        case progressionExercises
        case splitDays
        case sessions
        case sessionEntries
        case sessionSets
        case sessionReps
    }

    init(
        exercises: [ExerciseBackupDTO] = [],
        npExerciseExports: [NpExerciseExportDTO]? = nil,
        globalProgressionEnabled: Bool? = nil,
        globalDefaultProgressionProfileId: String? = nil,
        onboardingGoalsRaw: [String]? = nil,
        trainingExperienceRaw: String? = nil,
        routines: [RoutineBackupDTO] = [],
        programs: [ProgramBackupDTO] = [],
        programBlocks: [ProgramBlockBackupDTO] = [],
        programWorkouts: [ProgramWorkoutBackupDTO] = [],
        progressionProfiles: [ProgressionProfileBackupDTO] = [],
        progressionExercises: [ProgressionExerciseBackupDTO] = [],
        splitDays: [ExerciseSplitDayBackupDTO] = [],
        sessions: [SessionBackupDTO] = [],
        sessionEntries: [SessionEntryBackupDTO] = [],
        sessionSets: [SessionSetBackupDTO] = [],
        sessionReps: [SessionRepBackupDTO] = []
    ) {
        self.exercises = exercises
        self.npExerciseExports = npExerciseExports
        self.globalProgressionEnabled = globalProgressionEnabled
        self.globalDefaultProgressionProfileId = globalDefaultProgressionProfileId
        self.onboardingGoalsRaw = onboardingGoalsRaw
        self.trainingExperienceRaw = trainingExperienceRaw
        self.routines = routines
        self.programs = programs
        self.programBlocks = programBlocks
        self.programWorkouts = programWorkouts
        self.progressionProfiles = progressionProfiles
        self.progressionExercises = progressionExercises
        self.splitDays = splitDays
        self.sessions = sessions
        self.sessionEntries = sessionEntries
        self.sessionSets = sessionSets
        self.sessionReps = sessionReps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exercises = try container.decodeIfPresent([ExerciseBackupDTO].self, forKey: .exercises) ?? []
        npExerciseExports = try container.decodeIfPresent([NpExerciseExportDTO].self, forKey: .npExerciseExports)
        globalProgressionEnabled = try container.decodeIfPresent(Bool.self, forKey: .globalProgressionEnabled)
        globalDefaultProgressionProfileId = try container.decodeIfPresent(String.self, forKey: .globalDefaultProgressionProfileId)
        onboardingGoalsRaw = try container.decodeIfPresent([String].self, forKey: .onboardingGoalsRaw)
        trainingExperienceRaw = try container.decodeIfPresent(String.self, forKey: .trainingExperienceRaw)
        routines = try container.decodeIfPresent([RoutineBackupDTO].self, forKey: .routines) ?? []
        programs = try container.decodeIfPresent([ProgramBackupDTO].self, forKey: .programs) ?? []
        programBlocks = try container.decodeIfPresent([ProgramBlockBackupDTO].self, forKey: .programBlocks) ?? []
        programWorkouts = try container.decodeIfPresent([ProgramWorkoutBackupDTO].self, forKey: .programWorkouts) ?? []
        progressionProfiles = try container.decodeIfPresent([ProgressionProfileBackupDTO].self, forKey: .progressionProfiles) ?? []
        progressionExercises = try container.decodeIfPresent([ProgressionExerciseBackupDTO].self, forKey: .progressionExercises) ?? []
        splitDays = try container.decodeIfPresent([ExerciseSplitDayBackupDTO].self, forKey: .splitDays) ?? []
        sessions = try container.decodeIfPresent([SessionBackupDTO].self, forKey: .sessions) ?? []
        sessionEntries = try container.decodeIfPresent([SessionEntryBackupDTO].self, forKey: .sessionEntries) ?? []
        sessionSets = try container.decodeIfPresent([SessionSetBackupDTO].self, forKey: .sessionSets) ?? []
        sessionReps = try container.decodeIfPresent([SessionRepBackupDTO].self, forKey: .sessionReps) ?? []
    }
}

private struct NpExerciseExportDTO: Codable {
    let npId: String
    let exerciseAliases: [String]
}

private struct ExerciseBackupDTO: Codable {
    let id: String
    let npId: String?
    let name: String
    let aliases: [String]?
    let type: Int?
    let userId: String
    let primaryMuscles: [String]?
    let secondaryMuscles: [String]?
    let equipment: String?
    let category: String?
    let instructions: [String]?
    let images: [String]?
    let cachedMedia: Bool?
    let isUserCreated: Bool
    let isArchived: Bool?
    let timestamp: Date

    init(_ exercise: Exercise) {
        id = exercise.id.uuidString
        npId = exercise.npId
        name = exercise.name
        aliases = exercise.aliases
        type = exercise.type
        userId = exercise.user_id.uuidString
        primaryMuscles = exercise.primary_muscles
        secondaryMuscles = exercise.secondary_muscles
        equipment = exercise.equipment
        category = exercise.category
        instructions = exercise.instructions
        images = exercise.images
        cachedMedia = exercise.cachedMedia
        isUserCreated = exercise.isUserCreated
        isArchived = exercise.isArchived
        timestamp = exercise.timestamp
    }
}

private struct RoutineBackupDTO: Codable {
    let id: String
    let userId: String
    let order: Int
    let name: String
    let timestamp: Date
    let isArchived: Bool?
    let aliases: [String]?
    let defaultProgressionProfileId: String?
    let defaultProgressionProfileNameSnapshot: String?
    let splitDaySnapshot: [RoutineSplitDaySnapshotDTO]?
}

private struct RoutineSplitDaySnapshotDTO: Codable {
    let id: String
    let order: Int
    let exerciseId: String?
    let exerciseNpId: String?
}

private struct ProgramBackupDTO: Codable {
    let id: String
    let userId: String
    let name: String
    let notes: String
    let defaultProgressionProfileId: String?
    let defaultProgressionProfileNameSnapshot: String?
    let modeRaw: String
    let startDate: Date
    let trainDaysBeforeRest: Int
    let restDays: Int
    let isActive: Bool
    let isArchived: Bool?
    let timestamp: Date
    let createdAt: Date
    let updatedAt: Date
}

private struct ProgramBlockBackupDTO: Codable {
    let id: String
    let order: Int
    let name: String?
    let durationCount: Int
    let programId: String
}

private struct ProgramWorkoutBackupDTO: Codable {
    let id: String
    let order: Int
    let name: String?
    let weekdayIndex: Int?
    let routineNameSnapshot: String
    let programBlockId: String
    let routineId: String?
}

private struct ProgressionProfileBackupDTO: Codable {
    let id: String
    let userId: String?
    let name: String
    let miniDescription: String
    let typeRaw: String
    let incrementValue: Double
    let percentageIncreaseStored: Double?
    let incrementUnitRaw: Int
    let setIncrement: Int
    let successThreshold: Int
    let defaultSetsTarget: Int
    let defaultRepsTarget: Int?
    let defaultRepsLow: Int?
    let defaultRepsHigh: Int?
    let isBuiltIn: Bool
    let isArchived: Bool?
    let timestamp: Date
    let createdAt: Date
    let updatedAt: Date
}

private struct ProgressionExerciseBackupDTO: Codable {
    let id: String
    let userId: String
    let exerciseId: String
    let exerciseNameSnapshot: String
    let progressionProfileId: String?
    let progressionNameSnapshot: String?
    let progressionMiniDescriptionSnapshot: String?
    let progressionTypeRaw: String?
    let assignmentSourceRaw: String?
    let targetSetCount: Int
    let targetReps: Int?
    let targetRepsLow: Int?
    let targetRepsHigh: Int?
    let workingWeight: Double?
    let suggestedWeightLow: Double?
    let suggestedWeightHigh: Double?
    let workingWeightUnitRaw: Int
    let lastCompletedCycleWeight: Double?
    let lastCompletedCycleReps: Int?
    let lastCompletedCycleUnitRaw: Int?
    let successCount: Int
    let hasBackfilled: Bool
    let backfilledAt: Date?
    let lastEvaluatedSessionId: String?
    let timestamp: Date
    let createdAt: Date
    let updatedAt: Date
}

private struct ExerciseSplitDayBackupDTO: Codable {
    let id: String
    let order: Int
    let routineId: String
    let exerciseId: String?
    let exerciseNpId: String?
}

private struct SessionBackupDTO: Codable {
    let id: String
    let userId: String
    let timestamp: Date
    let timestampDone: Date
    let notes: String
    let routineId: String?
    let programId: String?
    let programBlockId: String?
    let programBlockName: String?
    let programWorkoutId: String?
    let programWorkoutName: String?
    let programWeekIndex: Int?
    let programSplitIndex: Int?
    let importHash: String?
}

private struct SessionEntryBackupDTO: Codable {
    let id: String
    let order: Int
    let isCompleted: Bool
    let sessionId: String
    let exerciseId: String?
    let exerciseNpId: String?
    let appliedProgressionProfileId: String?
    let appliedProgressionNameSnapshot: String?
    let appliedProgressionMiniDescriptionSnapshot: String?
    let appliedProgressionTypeRaw: String?
    let appliedTargetSetCount: Int?
    let appliedTargetReps: Int?
    let appliedTargetRepsLow: Int?
    let appliedTargetRepsHigh: Int?
    let appliedTargetWeight: Double?
    let appliedTargetWeightLow: Double?
    let appliedTargetWeightHigh: Double?
    let appliedTargetWeightUnitRaw: Int?
    let appliedProgressionCycleSummary: String?
}

private struct SessionSetBackupDTO: Codable {
    let id: String
    let order: Int
    let notes: String?
    let timestamp: Date
    let isCompleted: Bool
    let isDropSet: Bool
    let sessionEntryId: String
    let durationSeconds: Int?
    let distance: Double?
    let paceSeconds: Int?
    let distanceUnitRaw: String?
    let restSeconds: Int?
}

private struct SessionRepBackupDTO: Codable {
    let id: String
    let weight: Double
    let weightUnitRaw: Int
    let count: Int
    let notes: String?
    let sessionSetId: String
    let baseWeight: Double?
    let perSideWeight: Double?
    let isPerSide: Bool?
}
