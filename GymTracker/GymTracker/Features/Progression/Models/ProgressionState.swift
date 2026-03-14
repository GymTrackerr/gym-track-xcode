import Foundation
import SwiftData

@Model
final class ProgressionState {
    var id: UUID = UUID()
    var user_id: UUID

    // Optional so exercise archival/deletion paths can nullify safely.
    var exercise: Exercise?
    var progression: ProgressionProfile?

    var workingWeight: Double
    var successCount: Int
    var lastEvaluatedSessionEntryId: UUID?
    var lastAdvancedAt: Date?

    init(
        user_id: UUID,
        exercise: Exercise? = nil,
        progression: ProgressionProfile? = nil,
        workingWeight: Double = 0,
        successCount: Int = 0,
        lastEvaluatedSessionEntryId: UUID? = nil,
        lastAdvancedAt: Date? = nil
    ) {
        self.user_id = user_id
        self.exercise = exercise
        self.progression = progression
        self.workingWeight = workingWeight
        self.successCount = successCount
        self.lastEvaluatedSessionEntryId = lastEvaluatedSessionEntryId
        self.lastAdvancedAt = lastAdvancedAt
    }
}
