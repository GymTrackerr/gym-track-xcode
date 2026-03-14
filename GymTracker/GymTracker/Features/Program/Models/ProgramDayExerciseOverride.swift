import Foundation
import SwiftData

@Model
final class ProgramDayExerciseOverride {
    var id: UUID = UUID()
    var user_id: UUID

    // Optional so exercise archival/deletion paths can nullify safely.
    var exercise: Exercise?
    var programDay: ProgramDay
    var progression: ProgressionProfile?

    var setsTarget: Int?
    var repsTarget: Int?
    var repsLow: Int?
    var repsHigh: Int?
    var notes: String
    var order: Int

    init(
        user_id: UUID,
        programDay: ProgramDay,
        exercise: Exercise? = nil,
        progression: ProgressionProfile? = nil,
        setsTarget: Int? = nil,
        repsTarget: Int? = nil,
        repsLow: Int? = nil,
        repsHigh: Int? = nil,
        notes: String = "",
        order: Int
    ) {
        self.user_id = user_id
        self.programDay = programDay
        self.exercise = exercise
        self.progression = progression
        self.setsTarget = setsTarget
        self.repsTarget = repsTarget
        self.repsLow = repsLow
        self.repsHigh = repsHigh
        self.notes = notes
        self.order = order
    }
}
