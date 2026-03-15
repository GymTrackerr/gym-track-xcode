import Foundation
import SwiftData

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
        self.startDate = startDate
        self.currentWeekOverride = currentWeekOverride
        self.timestamp = Date()
        self.programDays = []
        self.blocks = []
        self.sessions = []
    }
}
