import Foundation
import SwiftData

enum SessionEntryResolver {
    static func ensureSessionEntry(for exercise: Exercise, in session: Session, context: ModelContext) -> SessionEntry {
        if let existing = preferredSessionEntry(for: exercise, in: session) {
            return existing
        }

        let newEntry = SessionEntry(
            order: session.sessionEntries.count,
            session: session,
            exercise: exercise
        )
        context.insert(newEntry)
        session.sessionEntries.append(newEntry)
        return newEntry
    }

    static func preferredSessionEntry(for exercise: Exercise, in session: Session) -> SessionEntry? {
        session.sessionEntries
            .filter { $0.exercise.id == exercise.id }
            .sorted { lhs, rhs in
                if lhs.order != rhs.order {
                    return lhs.order < rhs.order
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .first
    }
}
