import AppIntents
import Foundation

struct StartSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Session"
    static var description = IntentDescription("Start a blank session, routine session, or programme workout.")
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @Parameter(title: "Session Type")
    var sessionType: SessionStartKind?

    @Parameter(title: "Routine")
    var routine: SessionRoutineEntity?

    @Parameter(title: "Programme")
    var programme: SessionProgrammeEntity?

    @Parameter(title: "Note")
    var note: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Start \(\.$sessionType) session") {
            \.$routine
            \.$programme
            \.$note
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result: SessionIntentStore.StartResult
        switch try resolvedSessionType() {
        case .blank:
            result = try SessionIntentStore.startBlankSession(note: note)
        case .routine:
            result = try SessionIntentStore.startRoutineSession(routine: resolvedRoutine(), note: note)
        case .programme:
            result = try SessionIntentStore.startProgrammeSession(programme: resolvedProgramme(), note: note)
        }

        let action = result.openedExisting ? "Opened" : "Started"
        SessionIntentHandoff.requestActiveSession(sessionId: result.sessionId)
        return .result(dialog: "\(action) \(result.summary).")
    }

    private func resolvedSessionType() throws -> SessionStartKind {
        if let sessionType {
            return sessionType
        }
        if routine != nil {
            return .routine
        }
        if programme != nil {
            return .programme
        }
        throw $sessionType.needsValueError("Start a blank, routine, or programme session?")
    }

    private func resolvedRoutine() throws -> SessionRoutineEntity {
        guard let routine else {
            throw $routine.needsValueError("Which routine should I start?")
        }
        return routine
    }

    private func resolvedProgramme() throws -> SessionProgrammeEntity {
        guard let programme else {
            throw $programme.needsValueError("Which programme should I start?")
        }
        return programme
    }
}
