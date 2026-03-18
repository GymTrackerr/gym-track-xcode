import Foundation
import SwiftData

enum ProgramLengthMode: Int, CaseIterable, Identifiable {
    case fixedLength = 0
    case continuous = 1

    var id: Int { rawValue }
}

@Model
final class Program {
    var id: UUID = UUID()
    var user_id: UUID
    var name: String
    var notes: String
    var isArchived: Bool = false
    var isActive: Bool = false
    var isCurrent: Bool = false
    var isBuiltIn: Bool = false
    var builtInKey: String? = nil
    var lengthMode: Int
    var startDate: Date?
    var currentWeekOverride: Int?
    var timestamp: Date

    @Relationship(deleteRule: .nullify, inverse: \ProgramDay.program)
    var programDays: [ProgramDay]

    @Relationship(deleteRule: .cascade, inverse: \ProgramBlock.program)
    var blocks: [ProgramBlock]

    @Relationship(deleteRule: .nullify, inverse: \Session.program)
    var sessions: [Session]

    init(
        user_id: UUID,
        name: String,
        notes: String = "",
        isArchived: Bool = false,
        isActive: Bool = false,
        isCurrent: Bool = false,
        isBuiltIn: Bool = false,
        builtInKey: String? = nil,
        lengthMode: ProgramLengthMode = .fixedLength,
        startDate: Date? = nil,
        currentWeekOverride: Int? = nil
    ) {
        self.user_id = user_id
        self.name = name
        self.notes = notes
        self.isArchived = isArchived
        self.isActive = isActive
        self.isCurrent = isCurrent
        self.isBuiltIn = isBuiltIn
        self.builtInKey = builtInKey
        self.lengthMode = lengthMode.rawValue
        self.startDate = startDate
        self.currentWeekOverride = currentWeekOverride
        self.timestamp = Date()
        self.programDays = []
        self.blocks = []
        self.sessions = []
    }

    var resolvedProgramLengthMode: ProgramLengthMode {
        get { ProgramLengthMode(rawValue: lengthMode) ?? .fixedLength }
        set { lengthMode = newValue.rawValue }
    }
}
