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
    var startDate: Date?
    var timestamp: Date

    @Relationship(deleteRule: .nullify, inverse: \ProgramDay.program)
    var programDays: [ProgramDay]

    @Relationship(deleteRule: .nullify, inverse: \Session.program)
    var sessions: [Session]

    init(
        user_id: UUID,
        name: String,
        notes: String = "",
        isArchived: Bool = false,
        isActive: Bool = false,
        startDate: Date? = nil
    ) {
        self.user_id = user_id
        self.name = name
        self.notes = notes
        self.isArchived = isArchived
        self.isActive = isActive
        self.startDate = startDate
        self.timestamp = Date()
        self.programDays = []
        self.sessions = []
    }
}
