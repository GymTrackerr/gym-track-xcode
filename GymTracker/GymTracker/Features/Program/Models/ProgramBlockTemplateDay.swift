import Foundation
import SwiftData

@Model
final class ProgramBlockTemplateDay {
    var id: UUID = UUID()
    var user_id: UUID
    var title: String
    var weekDayIndex: Int
    var order: Int
    var notes: String
    var timestamp: Date

    // Optional so routine archival/deletion can nullify safely.
    var routine: Routine?

    var block: ProgramBlock?

    @Relationship(deleteRule: .nullify)
    var materializedProgramDays: [ProgramDay]

    init(
        user_id: UUID,
        block: ProgramBlock? = nil,
        routine: Routine? = nil,
        title: String,
        weekDayIndex: Int,
        order: Int,
        notes: String = ""
    ) {
        self.user_id = user_id
        self.block = block
        self.routine = routine
        self.title = title
        self.weekDayIndex = weekDayIndex
        self.order = order
        self.notes = notes
        self.timestamp = Date()
        self.materializedProgramDays = []
    }
}
