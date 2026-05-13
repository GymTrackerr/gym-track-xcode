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
        String(localized: titleResource)
    }

    var titleResource: LocalizedStringResource {
        switch self {
        case .weekly:
            return LocalizedStringResource(
                "programme.mode.weekly",
                defaultValue: "Weekly",
                table: "Programmes",
                comment: "Programme schedule mode that repeats by week"
            )
        case .continuous:
            return LocalizedStringResource(
                "programme.mode.continuous",
                defaultValue: "Continuous",
                table: "Programmes",
                comment: "Programme schedule mode that repeats through workouts continuously"
            )
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
        String(localized: shortTitleResource)
    }

    var shortTitleResource: LocalizedStringResource {
        switch self {
        case .monday:
            return LocalizedStringResource("programmes.weekday.short.monday", defaultValue: "Mon", table: "Programmes")
        case .tuesday:
            return LocalizedStringResource("programmes.weekday.short.tuesday", defaultValue: "Tue", table: "Programmes")
        case .wednesday:
            return LocalizedStringResource("programmes.weekday.short.wednesday", defaultValue: "Wed", table: "Programmes")
        case .thursday:
            return LocalizedStringResource("programmes.weekday.short.thursday", defaultValue: "Thu", table: "Programmes")
        case .friday:
            return LocalizedStringResource("programmes.weekday.short.friday", defaultValue: "Fri", table: "Programmes")
        case .saturday:
            return LocalizedStringResource("programmes.weekday.short.saturday", defaultValue: "Sat", table: "Programmes")
        case .sunday:
            return LocalizedStringResource("programmes.weekday.short.sunday", defaultValue: "Sun", table: "Programmes")
        }
    }

    var title: String {
        String(localized: titleResource)
    }

    var titleResource: LocalizedStringResource {
        switch self {
        case .monday:
            return LocalizedStringResource("programmes.weekday.monday", defaultValue: "Monday", table: "Programmes")
        case .tuesday:
            return LocalizedStringResource("programmes.weekday.tuesday", defaultValue: "Tuesday", table: "Programmes")
        case .wednesday:
            return LocalizedStringResource("programmes.weekday.wednesday", defaultValue: "Wednesday", table: "Programmes")
        case .thursday:
            return LocalizedStringResource("programmes.weekday.thursday", defaultValue: "Thursday", table: "Programmes")
        case .friday:
            return LocalizedStringResource("programmes.weekday.friday", defaultValue: "Friday", table: "Programmes")
        case .saturday:
            return LocalizedStringResource("programmes.weekday.saturday", defaultValue: "Saturday", table: "Programmes")
        case .sunday:
            return LocalizedStringResource("programmes.weekday.sunday", defaultValue: "Sunday", table: "Programmes")
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
    var continuousSkippedWorkoutCount: Int = 0
    var weeklySkipWeekOffset: Int? = nil
    var weeklySkipNextWorkoutId: UUID? = nil
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
            return String(localized: LocalizedStringResource("programmes.schedule.weeklySummary", defaultValue: "Weekly schedule", table: "Programmes"))
        case .continuous:
            return String(localized: LocalizedStringResource("programmes.schedule.continuousSummary", defaultValue: "\(trainDaysBeforeRest) on / \(restDays) off", table: "Programmes"))
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
    static let hiddenRepeatingBlockSentinel = "__continuous_repeat__"

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
        self.durationCount = max(durationCount, 0)
        self.workouts = []
    }

    var displayName: String {
        if isHiddenRepeatingBlock {
            return String(localized: LocalizedStringResource(
                "programmes.state.workoutRotation",
                defaultValue: "Workout Rotation",
                table: "Programmes"
            ))
        }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }
        let blockNumber = order + 1
        return String(localized: LocalizedStringResource(
            "programmes.block.defaultName",
            defaultValue: "Block \(blockNumber)",
            table: "Programmes"
        ))
    }

    var isHiddenRepeatingBlock: Bool {
        durationCount == 0 && name == Self.hiddenRepeatingBlockSentinel
    }

    var repeatsForever: Bool {
        durationCount == 0
    }
}

@Model
final class ProgramWorkout {
    var id: UUID = UUID()
    var order: Int
    var name: String?
    var weekdayIndex: Int?
    var routineIdSnapshot: UUID?
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
        self.routineIdSnapshot = routine?.id
        self.routineNameSnapshot = routine?.name ?? "Routine"
        self.name = name
        self.weekdayIndex = weekdayIndex
    }

    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }
        return routineNameSnapshot
    }

    var hasLinkedRoutine: Bool {
        routineIdSnapshot != nil
    }

    func updateRoutineLink(_ routine: Routine?) {
        self.routine = routine
        self.routineIdSnapshot = routine?.id
        if let routine {
            let trimmed = routine.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                self.routineNameSnapshot = trimmed
            }
        }
    }

    var resolvedWeekday: ProgramWeekday? {
        guard let weekdayIndex else { return nil }
        return ProgramWeekday(rawValue: weekdayIndex)
    }

    var scheduleLabel: String? {
        resolvedWeekday?.title
    }
}
