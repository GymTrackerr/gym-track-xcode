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
    var soft_deleted: Bool = false
    var syncMetaId: UUID? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    var routine: Routine?
    var routine_id: UUID? { routine?.id }

    var program: Program?
    var program_id: UUID? { program?.id }
    var programBlockId: UUID? = nil
    var programBlockName: String? = nil
    var programWorkoutId: UUID? = nil
    var programWorkoutName: String? = nil
    var programWeekIndex: Int? = nil
    var programSplitIndex: Int? = nil
    
    @Relationship(deleteRule: .cascade)
    var sessionEntries: [SessionEntry]

    init (timestamp: Date, user_id: UUID, routine: Routine?, notes: String, program: Program? = nil) {
        self.timestamp = timestamp
        self.user_id = user_id
        self.notes = notes
        self.routine = routine
        self.program = program
        self.timestampDone = timestamp
        self.createdAt = timestamp
        self.updatedAt = timestamp
        self.sessionEntries = []
    }
}

extension Session: SyncTrackedRoot {
    static var syncModelType: SyncModelType { .session }
    var syncLinkedItemId: String { id.uuidString.lowercased() }

    var syncSeedDate: Date { timestamp }
}

enum SessionNavigationContext: Hashable {
    case active(sessionId: UUID)
    case activePreferred(sessionId: UUID, exerciseId: UUID)
    case past(sessionId: UUID)
    case pastPreferred(sessionId: UUID, exerciseId: UUID)
    case fromExerciseHistory(sessionId: UUID, exerciseId: UUID)

    var sessionId: UUID {
        switch self {
        case .active(let sessionId):
            return sessionId
        case .activePreferred(let sessionId, _):
            return sessionId
        case .past(let sessionId):
            return sessionId
        case .pastPreferred(let sessionId, _):
            return sessionId
        case .fromExerciseHistory(let sessionId, _):
            return sessionId
        }
    }

    var isEditableByDefault: Bool {
        switch self {
        case .active, .activePreferred, .pastPreferred:
            return true
        case .past, .fromExerciseHistory:
            return false
        }
    }

    var allowsUnlock: Bool {
        switch self {
        case .active, .activePreferred, .pastPreferred:
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

    var preferredExerciseId: UUID? {
        switch self {
        case .activePreferred(_, let exerciseId):
            return exerciseId
        case .pastPreferred(_, let exerciseId):
            return exerciseId
        case .fromExerciseHistory(_, let exerciseId):
            return exerciseId
        case .active, .past:
            return nil
        }
    }

    var statusBadgeText: String {
        switch self {
        case .active, .activePreferred:
            return "Current session"
        case .pastPreferred:
            return "Logging exercise"
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

    static func loggingContext(for session: Session, exerciseId: UUID) -> SessionNavigationContext {
        if session.timestampDone == session.timestamp {
            return .activePreferred(sessionId: session.id, exerciseId: exerciseId)
        }
        return .pastPreferred(sessionId: session.id, exerciseId: exerciseId)
    }
}
