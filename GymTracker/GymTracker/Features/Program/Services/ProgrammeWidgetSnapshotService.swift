import Foundation
import WidgetKit

final class ProgrammeWidgetSnapshotService {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    func refresh(
        user: User,
        activeProgram: Program?,
        state: ProgramResolvedState?,
        activeSession: Session?,
        reloadTimelines: Bool = true
    ) {
        let snapshot = buildSnapshot(
            user: user,
            activeProgram: activeProgram,
            state: state,
            activeSession: activeSession
        )

        try? ProgrammeWidgetSnapshotStore.save(snapshot)
        if reloadTimelines {
            WidgetCenter.shared.reloadTimelines(ofKind: ProgrammeWidgetSnapshotStore.widgetKind)
        }
    }

    func clear(reloadTimelines: Bool = true) {
        ProgrammeWidgetSnapshotStore.clear()
        if reloadTimelines {
            WidgetCenter.shared.reloadTimelines(ofKind: ProgrammeWidgetSnapshotStore.widgetKind)
        }
    }

    private func buildSnapshot(
        user: User,
        activeProgram: Program?,
        state: ProgramResolvedState?,
        activeSession: Session?
    ) -> ProgrammeWidgetSnapshot {
        let scopedActiveSession = activeSession?.user_id == user.id ? activeSession : nil
        let activeSessionName = scopedActiveSession.map(sessionTitle)
        let activeSessionDetail = scopedActiveSession.map(sessionDetail)

        return ProgrammeWidgetSnapshot(
            activeProgrammeName: activeProgram?.name,
            programmeStatus: state?.progressLabel,
            programmeDetail: programmeDetail(for: activeProgram, state: state),
            nextWorkoutName: state?.nextWorkoutLabel,
            activeSessionName: activeSessionName,
            activeSessionDetail: activeSessionDetail,
            hasProgramme: activeProgram != nil,
            hasActiveSession: scopedActiveSession != nil,
            updatedAt: Date()
        )
    }

    private func programmeDetail(for program: Program?, state: ProgramResolvedState?) -> String? {
        guard let program else { return nil }
        guard let state else { return program.scheduleSummary }

        let block = state.blockLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let schedule = state.scheduleLabel.trimmingCharacters(in: .whitespacesAndNewlines)

        if !block.isEmpty && block != schedule {
            return "\(block) - \(schedule)"
        }
        return schedule.isEmpty ? program.scheduleSummary : schedule
    }

    private func sessionTitle(for session: Session) -> String {
        if let programWorkoutName = trimmed(session.programWorkoutName) {
            return programWorkoutName
        }
        if let routineName = trimmed(session.routine?.name) {
            return routineName
        }
        if let programName = trimmed(session.program?.name) {
            return programName
        }
        return "Open Session"
    }

    private func sessionDetail(for session: Session) -> String {
        let started = "Started \(Self.timeFormatter.string(from: session.timestamp))"
        if let programName = trimmed(session.program?.name) {
            return "\(programName) - \(started)"
        }
        return started
    }

    private func trimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
