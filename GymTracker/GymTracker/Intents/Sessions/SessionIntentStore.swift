import Foundation
import SwiftData

@MainActor
enum SessionIntentStore {
    struct StartResult {
        let sessionId: UUID
        let summary: String
        let openedExisting: Bool
    }

    private struct IntentEnvironment {
        let container: ModelContainer
        let context: ModelContext
        let routineService: RoutineService
        let programService: ProgramService
        let sessionService: SessionService
    }

    enum IntentError: LocalizedError {
        case noAccount
        case unavailableRoutine
        case unavailableProgramme
        case noProgrammeWorkout(String)
        case programmeWorkoutNotStartable(String)
        case unableToStart(String)

        var errorDescription: String? {
            switch self {
            case .noAccount:
                return "Create or sign in to an account before starting a session."
            case .unavailableRoutine:
                return "That routine is no longer available."
            case .unavailableProgramme:
                return "That programme is no longer available."
            case .noProgrammeWorkout(let name):
                return "\(name) does not have a next workout to start."
            case .programmeWorkoutNotStartable(let name):
                return "\(name) needs a linked routine before Siri can start it."
            case .unableToStart(let reason):
                return reason
            }
        }
    }

    static func startBlankSession(note: String?) throws -> StartResult {
        let environment = try makeEnvironment()
        environment.sessionService.create_notes = normalizedOptionalText(note) ?? ""
        environment.sessionService.selectRoutine(nil)

        guard let session = environment.sessionService.addSession() else {
            throw IntentError.unableToStart("Could not start a blank session.")
        }

        refreshProgrammeWidget(environment)
        return StartResult(sessionId: session.id, summary: "blank session", openedExisting: false)
    }

    static func startRoutineSession(routine entity: SessionRoutineEntity, note: String?) throws -> StartResult {
        let environment = try makeEnvironment()
        guard let routine = environment.routineService.routines.first(where: { $0.id == entity.id }) else {
            throw IntentError.unavailableRoutine
        }

        environment.sessionService.create_notes = normalizedOptionalText(note) ?? ""
        environment.sessionService.selectRoutine(routine)

        guard let session = environment.sessionService.addSession() else {
            throw IntentError.unableToStart("Could not start \(routine.name).")
        }

        refreshProgrammeWidget(environment)
        return StartResult(sessionId: session.id, summary: "\(routine.name) session", openedExisting: false)
    }

    static func startProgrammeSession(programme entity: SessionProgrammeEntity, note: String?) throws -> StartResult {
        let environment = try makeEnvironment()
        guard let programme = environment.programService.programs.first(where: { $0.id == entity.id }) else {
            throw IntentError.unavailableProgramme
        }

        let state = environment.programService.resolvedState(
            for: programme,
            sessions: environment.sessionService.sessions
        )

        if let activeSession = state.activeSession {
            refreshProgrammeWidget(environment)
            return StartResult(
                sessionId: activeSession.id,
                summary: sessionSummary(activeSession),
                openedExisting: true
            )
        }

        guard let workout = state.nextWorkout else {
            throw IntentError.noProgrammeWorkout(programme.name)
        }

        guard state.canStartNextWorkout else {
            throw IntentError.programmeWorkoutNotStartable(workout.displayName)
        }

        environment.sessionService.create_notes = normalizedOptionalText(note) ?? ""
        guard let session = environment.sessionService.startProgramWorkout(program: programme, workout: workout) else {
            throw IntentError.unableToStart("Could not start \(workout.displayName).")
        }

        refreshProgrammeWidget(environment)
        return StartResult(
            sessionId: session.id,
            summary: "\(workout.displayName) from \(programme.name)",
            openedExisting: false
        )
    }

    static func routineEntities(identifiers: [UUID]) throws -> [SessionRoutineEntity] {
        let environment = try makeEnvironment()
        return orderedMatches(
            identifiers: identifiers,
            items: environment.routineService.routines,
            id: \.id
        )
        .map(routineEntity)
    }

    static func routineEntities(matching string: String) throws -> [SessionRoutineEntity] {
        let environment = try makeEnvironment()
        let query = normalizedOptionalText(string)
        let routines = query.map(environment.routineService.search(query:)) ?? environment.routineService.routines
        return Array(routines.prefix(20)).map(routineEntity)
    }

    static func suggestedRoutineEntities() throws -> [SessionRoutineEntity] {
        let environment = try makeEnvironment()
        return Array(environment.routineService.routines.prefix(20)).map(routineEntity)
    }

    static func programmeEntities(identifiers: [UUID]) throws -> [SessionProgrammeEntity] {
        let environment = try makeEnvironment()
        return orderedMatches(
            identifiers: identifiers,
            items: environment.programService.programs,
            id: \.id
        )
        .map(programmeEntity)
    }

    static func programmeEntities(matching string: String) throws -> [SessionProgrammeEntity] {
        let environment = try makeEnvironment()
        guard let query = normalizedOptionalText(string) else {
            return Array(orderedProgrammes(environment.programService.programs).prefix(20)).map(programmeEntity)
        }

        return Array(
            orderedProgrammes(environment.programService.programs)
                .filter { $0.name.localizedCaseInsensitiveContains(query) }
                .prefix(20)
        )
        .map(programmeEntity)
    }

    static func suggestedProgrammeEntities() throws -> [SessionProgrammeEntity] {
        let environment = try makeEnvironment()
        return Array(orderedProgrammes(environment.programService.programs).prefix(20)).map(programmeEntity)
    }

    private static func makeEnvironment() throws -> IntentEnvironment {
        let container = SharedModelConfig.createSharedModelContainer()
        let context = ModelContext(container)
        let user = try currentUser(in: context)

        let routineRepository = LocalRoutineRepository(modelContext: context)
        let programRepository = LocalProgramRepository(modelContext: context)
        let sessionRepository = LocalSessionRepository(modelContext: context)
        let progressionRepository = LocalProgressionRepository(modelContext: context)

        let routineService = RoutineService(context: context, repository: routineRepository)
        let programService = ProgramService(context: context, repository: programRepository)
        let sessionService = SessionService(context: context, repository: sessionRepository)
        let progressionService = ProgressionService(
            context: context,
            repository: progressionRepository,
            historyRepository: sessionRepository
        )

        routineService.currentUser = user
        routineService.loadSplitDays()

        programService.currentUser = user
        programService.loadPrograms()

        progressionService.currentUser = user
        progressionService.loadFeature()

        sessionService.currentUser = user
        sessionService.progressionService = progressionService
        sessionService.programService = programService
        sessionService.loadSessions()

        return IntentEnvironment(
            container: container,
            context: context,
            routineService: routineService,
            programService: programService,
            sessionService: sessionService
        )
    }

    private static func currentUser(in context: ModelContext) throws -> User {
        let descriptor = FetchDescriptor<User>(
            sortBy: [SortDescriptor(\.lastLogin, order: .reverse)]
        )
        let users = try context.fetch(descriptor).filter { !$0.soft_deleted }
        guard let user = users.first else {
            throw IntentError.noAccount
        }
        return user
    }

    private static func routineEntity(_ routine: Routine) -> SessionRoutineEntity {
        SessionRoutineEntity(
            id: routine.id,
            name: routine.name,
            subtitle: routineSubtitle(routine)
        )
    }

    private static func programmeEntity(_ programme: Program) -> SessionProgrammeEntity {
        SessionProgrammeEntity(
            id: programme.id,
            name: programme.name,
            subtitle: programmeSubtitle(programme)
        )
    }

    private static func routineSubtitle(_ routine: Routine) -> String {
        let count = routine.exerciseSplits.count
        if count == 1 {
            return "1 exercise"
        }
        return "\(count) exercises"
    }

    private static func programmeSubtitle(_ programme: Program) -> String {
        if programme.isActive {
            return "Active - \(programme.scheduleSummary)"
        }
        return programme.scheduleSummary
    }

    private static func orderedProgrammes(_ programmes: [Program]) -> [Program] {
        programmes.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive {
                return lhs.isActive && !rhs.isActive
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static func orderedMatches<Item>(
        identifiers: [UUID],
        items: [Item],
        id: KeyPath<Item, UUID>
    ) -> [Item] {
        let order = Dictionary(uniqueKeysWithValues: identifiers.enumerated().map { ($1, $0) })
        return items
            .filter { order[$0[keyPath: id]] != nil }
            .sorted { (order[$0[keyPath: id]] ?? 0) < (order[$1[keyPath: id]] ?? 0) }
    }

    private static func sessionSummary(_ session: Session) -> String {
        if let programWorkoutName = normalizedOptionalText(session.programWorkoutName) {
            return programWorkoutName
        }
        if let routineName = normalizedOptionalText(session.routine?.name) {
            return routineName
        }
        if let programName = normalizedOptionalText(session.program?.name) {
            return programName
        }
        return "active session"
    }

    private static func refreshProgrammeWidget(_ environment: IntentEnvironment) {
        environment.programService.loadPrograms()
        environment.sessionService.loadSessions()
        environment.programService.refreshWidgetSnapshot(sessions: environment.sessionService.sessions)
    }

    private static func normalizedOptionalText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
