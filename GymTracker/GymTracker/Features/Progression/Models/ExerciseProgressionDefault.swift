import Foundation
import SwiftData

@Model
final class ExerciseProgressionDefault {
    var id: UUID = UUID()
    var user_id: UUID
    var timestamp: Date

    @Relationship(deleteRule: .nullify)
    var exercise: Exercise?

    @Relationship(deleteRule: .nullify)
    var progression: ProgressionProfile?

    var setsTarget: Int?
    var repsTarget: Int?
    var repsLow: Int?
    var repsHigh: Int?

    init(
        user_id: UUID,
        exercise: Exercise? = nil,
        progression: ProgressionProfile? = nil,
        setsTarget: Int? = nil,
        repsTarget: Int? = nil,
        repsLow: Int? = nil,
        repsHigh: Int? = nil
    ) {
        self.user_id = user_id
        self.timestamp = Date()
        self.exercise = exercise
        self.progression = progression
        self.setsTarget = setsTarget
        self.repsTarget = repsTarget
        self.repsLow = repsLow
        self.repsHigh = repsHigh
    }
}
