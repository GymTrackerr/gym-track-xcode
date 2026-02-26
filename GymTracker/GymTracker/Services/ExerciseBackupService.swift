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
        guard let userId = currentUserProvider()?.id else {
            throw BackupError.missingUser
        }

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
                exerciseNpId: exerciseNpId
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
            RoutineBackupDTO(
                id: $0.id.uuidString,
                userId: $0.user_id.uuidString,
                order: $0.order,
                name: $0.name,
                timestamp: $0.timestamp,
                isArchived: $0.isArchived,
                aliases: $0.aliases
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
                routines: routineDTOs,
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
            try data.write(to: fileURL, options: .atomic)
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
            routinesById[routineId] = routine
        }

        let existingSessions = try fetchSessions(userId: userId)
        var sessionsById = Dictionary(uniqueKeysWithValues: existingSessions.map { ($0.id, $0) })

        for dto in root.payload.sessions {
            let sessionId = try uuid(from: dto.id, label: "session.id")
            _ = try uuid(from: dto.userId, label: "session.userId")

            let routine: Routine?
            if let routineIdString = dto.routineId {
                let routineId = try uuid(from: routineIdString, label: "session.routineId")
                guard let linkedRoutine = routinesById[routineId] else {
                    throw BackupError.invalidBackup("Session \(dto.id) references missing routine.")
                }
                routine = linkedRoutine
            } else {
                routine = nil
            }

            let session: Session
            if let existing = sessionsById[sessionId] {
                session = existing
                report.sessions.updated += 1
            } else {
                session = Session(timestamp: dto.timestamp, user_id: userId, routine: routine, notes: dto.notes)
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
            if !session.sessionEntries.contains(where: { $0.id == entry.id }) {
                session.sessionEntries.append(entry)
            }
            entriesById[entryId] = entry
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

        for dto in root.payload.splitDays {
            let splitDayId = try uuid(from: dto.id, label: "splitDay.id")
            let routineId = try uuid(from: dto.routineId, label: "splitDay.routineId")
            guard let routine = routinesById[routineId] else {
                throw BackupError.invalidBackup("Split day \(dto.id) references missing routine.")
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

        let routines = try fetchRoutines(userId: userId)
        for routine in routines { modelContext.delete(routine) }
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
        guard !payload.sessionEntries.isEmpty || !payload.splitDays.isEmpty else { return }

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

        if sessionReferencesPayload || splitReferencesPayload {
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
}

private struct ExercisePayloadDTO: Codable {
    let exercises: [ExerciseBackupDTO]
    let npExerciseExports: [NpExerciseExportDTO]?
    let routines: [RoutineBackupDTO]
    let splitDays: [ExerciseSplitDayBackupDTO]
    let sessions: [SessionBackupDTO]
    let sessionEntries: [SessionEntryBackupDTO]
    let sessionSets: [SessionSetBackupDTO]
    let sessionReps: [SessionRepBackupDTO]
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
    let importHash: String?
}

private struct SessionEntryBackupDTO: Codable {
    let id: String
    let order: Int
    let isCompleted: Bool
    let sessionId: String
    let exerciseId: String?
    let exerciseNpId: String?
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
