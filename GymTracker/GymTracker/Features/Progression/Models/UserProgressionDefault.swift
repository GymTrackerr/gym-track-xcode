import Foundation
import SwiftData

@Model
final class UserProgressionDefault {
    var id: UUID = UUID()
    var user_id: UUID
    var timestamp: Date

    @Relationship(deleteRule: .nullify)
    var progression: ProgressionProfile?

    var setsTarget: Int?
    var repsTarget: Int?
    var repsLow: Int?
    var repsHigh: Int?

    init(
        user_id: UUID,
        progression: ProgressionProfile? = nil,
        setsTarget: Int? = nil,
        repsTarget: Int? = nil,
        repsLow: Int? = nil,
        repsHigh: Int? = nil
    ) {
        self.user_id = user_id
        self.timestamp = Date()
        self.progression = progression
        self.setsTarget = setsTarget
        self.repsTarget = repsTarget
        self.repsLow = repsLow
        self.repsHigh = repsHigh
    }
}
