import Foundation

struct ProgrammeWidgetSnapshot: Codable, Hashable {
    let activeProgrammeName: String?
    let programmeStatus: String?
    let programmeDetail: String?
    let nextWorkoutName: String?
    let activeSessionName: String?
    let activeSessionDetail: String?
    let hasProgramme: Bool
    let hasActiveSession: Bool
    let updatedAt: Date

    static var placeholder: ProgrammeWidgetSnapshot {
        ProgrammeWidgetSnapshot(
            activeProgrammeName: "Strength Block",
            programmeStatus: "Week 2 of 4",
            programmeDetail: "Upper / Lower",
            nextWorkoutName: "Upper Body",
            activeSessionName: "Lower Body",
            activeSessionDetail: "Started 09:30",
            hasProgramme: true,
            hasActiveSession: true,
            updatedAt: Date()
        )
    }

    static var empty: ProgrammeWidgetSnapshot {
        ProgrammeWidgetSnapshot(
            activeProgrammeName: nil,
            programmeStatus: nil,
            programmeDetail: nil,
            nextWorkoutName: nil,
            activeSessionName: nil,
            activeSessionDetail: nil,
            hasProgramme: false,
            hasActiveSession: false,
            updatedAt: Date()
        )
    }
}

enum ProgrammeWidgetSnapshotStore {
    static let widgetKind = "ProgrammeWidget"

    private static let appGroupIdentifier = "group.net.novapro.GymTracker"
    private static let snapshotKey = "programme.widget.snapshot.v1"

    static func load() -> ProgrammeWidgetSnapshot? {
        guard
            let defaults = UserDefaults(suiteName: appGroupIdentifier),
            let data = defaults.data(forKey: snapshotKey)
        else {
            return nil
        }
        return try? JSONDecoder().decode(ProgrammeWidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: ProgrammeWidgetSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    static func clear() {
        UserDefaults(suiteName: appGroupIdentifier)?.removeObject(forKey: snapshotKey)
    }
}
