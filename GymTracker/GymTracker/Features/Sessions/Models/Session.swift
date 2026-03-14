//
//  Workout.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import Foundation
import SwiftData

@Model
final class Session {
    var id: UUID = UUID()
    var user_id: UUID
    var timestamp: Date
    var timestampDone: Date = Date() // temporary just saving as 
    var notes: String = ""
    var importHash: String? = nil
    
    var routine: Routine?
    var routine_id: UUID? { routine?.id }

    var program: Program?
    var programDay: ProgramDay?
    var programWeekIndex: Int?
    var programBlockIndex: Int?
    
    @Relationship(deleteRule: .cascade)
    var sessionEntries: [SessionEntry]

    init (timestamp: Date, user_id: UUID, routine: Routine?, notes: String) {
        self.timestamp = timestamp
        self.user_id = user_id
        self.notes = notes
        self.routine = routine
        self.program = nil
        self.programDay = nil
        self.programWeekIndex = nil
        self.programBlockIndex = nil
        self.timestampDone = timestamp
        self.sessionEntries = []
    }
}

enum SessionNavigationContext: Equatable {
    case active(sessionId: UUID)
    case past(sessionId: UUID)
    case fromExerciseHistory(sessionId: UUID, exerciseId: UUID)

    var sessionId: UUID {
        switch self {
        case .active(let sessionId):
            return sessionId
        case .past(let sessionId):
            return sessionId
        case .fromExerciseHistory(let sessionId, _):
            return sessionId
        }
    }

    var isEditableByDefault: Bool {
        switch self {
        case .active:
            return true
        case .past, .fromExerciseHistory:
            return false
        }
    }

    var allowsUnlock: Bool {
        switch self {
        case .active:
            return false
        case .past, .fromExerciseHistory:
            return true
        }
    }

    var isFromExerciseHistory: Bool {
        if case .fromExerciseHistory = self {
            return true
        }
        return false
    }

    var statusBadgeText: String {
        switch self {
        case .active:
            return "Current session"
        case .past, .fromExerciseHistory:
            return "Past session"
        }
    }

    static func forSession(_ session: Session) -> SessionNavigationContext {
        if session.timestampDone == session.timestamp {
            return .active(sessionId: session.id)
        }
        return .past(sessionId: session.id)
    }
}
