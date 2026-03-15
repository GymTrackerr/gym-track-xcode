import Foundation
import SwiftData

@Model
final class ProgramDay {
    var id: UUID = UUID()
    var user_id: UUID

    // Optional so routine deletion can safely nullify without cascading program data.
    var routine: Routine?
    var program: Program?
    var sourceBlock: ProgramBlock?
    var sourceTemplateDay: ProgramBlockTemplateDay?
    var isGeneratedFromTemplate: Bool
    var generationKey: String?

    var weekIndex: Int
    var dayIndex: Int
    var blockIndex: Int?
    var title: String
    var order: Int

    @Relationship(deleteRule: .cascade, inverse: \ProgramDayExerciseOverride.programDay)
    var exerciseOverrides: [ProgramDayExerciseOverride]

    @Relationship(deleteRule: .nullify, inverse: \Session.programDay)
    var sessions: [Session]

    init(
        user_id: UUID,
        program: Program? = nil,
        routine: Routine? = nil,
        sourceBlock: ProgramBlock? = nil,
        sourceTemplateDay: ProgramBlockTemplateDay? = nil,
        isGeneratedFromTemplate: Bool = false,
        generationKey: String? = nil,
        weekIndex: Int,
        dayIndex: Int,
        blockIndex: Int? = nil,
        title: String,
        order: Int
    ) {
        self.user_id = user_id
        self.program = program
        self.routine = routine
        self.sourceBlock = sourceBlock
        self.sourceTemplateDay = sourceTemplateDay
        self.isGeneratedFromTemplate = isGeneratedFromTemplate
        self.generationKey = generationKey
        self.weekIndex = weekIndex
        self.dayIndex = dayIndex
        self.blockIndex = blockIndex
        self.title = title
        self.order = order
        self.exerciseOverrides = []
        self.sessions = []
    }
}
