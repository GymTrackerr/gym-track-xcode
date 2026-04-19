//
//  Program.swift
//  GymTracker
//
//  Created by Codex on 2026-04-19.
//

import Foundation
import SwiftData

enum ProgramMode: String, Codable, CaseIterable, Identifiable {
    case weekly
    case continuous

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly:
            return "Weekly"
        case .continuous:
            return "Continuous"
        }
    }
}

enum ProgramWeekday: Int, Codable, CaseIterable, Identifiable {
    case monday = 1
    case tuesday = 2
    case wednesday = 3
    case thursday = 4
    case friday = 5
    case saturday = 6
    case sunday = 7

    var id: Int { rawValue }

    var shortTitle: String {
        switch self {
        case .monday:
            return "Mon"
        case .tuesday:
            return "Tue"
        case .wednesday:
            return "Wed"
        case .thursday:
            return "Thu"
        case .friday:
            return "Fri"
        case .saturday:
            return "Sat"
        case .sunday:
            return "Sun"
        }
    }

    var title: String {
        switch self {
        case .monday:
            return "Monday"
        case .tuesday:
            return "Tuesday"
        case .wednesday:
            return "Wednesday"
        case .thursday:
            return "Thursday"
        case .friday:
            return "Friday"
        case .saturday:
            return "Saturday"
        case .sunday:
            return "Sunday"
        }
    }

    static func mondayBasedIndex(for date: Date, calendar: Calendar = .current) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }
}

@Model
final class Program {
    var id: UUID = UUID()
    var user_id: UUID
    var name: String
    var notes: String
    var defaultProgressionProfileId: UUID? = nil
    var defaultProgressionProfileNameSnapshot: String? = nil
    var modeRaw: String
    var startDate: Date
    var trainDaysBeforeRest: Int
    var restDays: Int
    var isActive: Bool = false
    var isArchived: Bool = false
    var soft_deleted: Bool = false
    var syncMetaId: UUID? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var timestamp: Date

    @Relationship(deleteRule: .cascade)
    var blocks: [ProgramBlock]

    @Relationship(deleteRule: .nullify)
    var sessions: [Session]

    init(
        userId: UUID,
        name: String,
        notes: String = "",
        mode: ProgramMode,
        startDate: Date = Date(),
        trainDaysBeforeRest: Int = 3,
        restDays: Int = 1
    ) {
        let timestamp = Date()
        self.user_id = userId
        self.name = name
        self.notes = notes
        self.modeRaw = mode.rawValue
        self.startDate = startDate
        self.trainDaysBeforeRest = max(trainDaysBeforeRest, 1)
        self.restDays = max(restDays, 0)
        self.timestamp = timestamp
        self.createdAt = timestamp
        self.updatedAt = timestamp
        self.blocks = []
        self.sessions = []
    }

    var mode: ProgramMode {
        get { ProgramMode(rawValue: modeRaw) ?? .weekly }
        set { modeRaw = newValue.rawValue }
    }

    var scheduleSummary: String {
        switch mode {
        case .weekly:
            return "Weekly schedule"
        case .continuous:
            return "\(trainDaysBeforeRest) on / \(restDays) off"
        }
    }
}

extension Program: SyncTrackedRoot {
    static var syncModelType: SyncModelType { .program }
    var syncLinkedItemId: String { id.uuidString.lowercased() }
    var syncSeedDate: Date { timestamp }
    var legacyDeleteBridgeValue: Bool? { isArchived }

    func applyLegacyDeleteBridge(_ value: Bool) {
        isArchived = value
    }
}

@Model
final class ProgramBlock {
    var id: UUID = UUID()
    var order: Int
    var name: String?
    var durationCount: Int
    var program: Program

    @Relationship(deleteRule: .cascade)
    var workouts: [ProgramWorkout]

    init(order: Int, program: Program, name: String? = nil, durationCount: Int = 4) {
        self.order = order
        self.program = program
        self.name = name
        self.durationCount = max(durationCount, 1)
        self.workouts = []
    }

    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }
        return "Block \(order + 1)"
    }
}

@Model
final class ProgramWorkout {
    var id: UUID = UUID()
    var order: Int
    var name: String?
    var weekdayIndex: Int?
    var routineNameSnapshot: String
    var programBlock: ProgramBlock
    var routine: Routine?

    init(
        order: Int,
        programBlock: ProgramBlock,
        routine: Routine?,
        name: String? = nil,
        weekdayIndex: Int? = nil
    ) {
        self.order = order
        self.programBlock = programBlock
        self.routine = routine
        self.routineNameSnapshot = routine?.name ?? "Routine"
        self.name = name
        self.weekdayIndex = weekdayIndex
    }

    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }
        return routine?.name ?? routineNameSnapshot
    }

    var resolvedWeekday: ProgramWeekday? {
        guard let weekdayIndex else { return nil }
        return ProgramWeekday(rawValue: weekdayIndex)
    }

    var scheduleLabel: String? {
        resolvedWeekday?.title
    }
}
