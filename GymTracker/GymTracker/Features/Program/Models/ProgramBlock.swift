import Foundation
import SwiftData

@Model
final class ProgramBlock {
    var id: UUID = UUID()
    var user_id: UUID
    var title: String
    var notes: String
    var startWeekIndex: Int
    var endWeekIndex: Int
    var order: Int
    var isArchived: Bool
    var timestamp: Date

    var program: Program?

    @Relationship(deleteRule: .cascade)
    var templateDays: [ProgramBlockTemplateDay]

    @Relationship(deleteRule: .nullify)
    var materializedProgramDays: [ProgramDay]

    init(
        user_id: UUID,
        program: Program? = nil,
        title: String,
        notes: String = "",
        startWeekIndex: Int,
        endWeekIndex: Int,
        order: Int,
        isArchived: Bool = false
    ) {
        self.user_id = user_id
        self.program = program
        self.title = title
        self.notes = notes
        self.startWeekIndex = startWeekIndex
        self.endWeekIndex = endWeekIndex
        self.order = order
        self.isArchived = isArchived
        self.timestamp = Date()
        self.templateDays = []
        self.materializedProgramDays = []
    }
}
