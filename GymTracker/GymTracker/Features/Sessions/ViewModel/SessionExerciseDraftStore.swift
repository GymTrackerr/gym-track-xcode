import SwiftUI
import Combine

@MainActor
final class SessionExerciseDraftStore: ObservableObject {
    struct RepDraftSnapshot: Equatable {
        var id: UUID
        var weight: Double
        var reps: Int
        var unit: WeightUnit
    }

    struct SessionExerciseDraft: Equatable {
        var hasSeeded: Bool = false
        var isDropSetEnabled: Bool = false
        var repDrafts: [RepDraftSnapshot] = []
        var dropSetWeightDrafts: [UUID: String] = [:]
        var dropSetRepsDrafts: [UUID: String] = [:]
        var dropSetInlineHint: String? = nil
    }

    @Published private(set) var draftsBySessionExerciseId: [UUID: SessionExerciseDraft] = [:]

    func hasDraft(for sessionExerciseId: UUID) -> Bool {
        draftsBySessionExerciseId[sessionExerciseId] != nil
    }

    func draft(for sessionExerciseId: UUID) -> SessionExerciseDraft? {
        draftsBySessionExerciseId[sessionExerciseId]
    }

    func setDraft(_ draft: SessionExerciseDraft, for sessionExerciseId: UUID) {
        draftsBySessionExerciseId[sessionExerciseId] = draft
    }

    func updateDraft(for sessionExerciseId: UUID, _ mutate: (inout SessionExerciseDraft) -> Void) {
        var draft = draftsBySessionExerciseId[sessionExerciseId] ?? SessionExerciseDraft()
        mutate(&draft)
        draftsBySessionExerciseId[sessionExerciseId] = draft
    }

    func clearDraft(for sessionExerciseId: UUID) {
        draftsBySessionExerciseId.removeValue(forKey: sessionExerciseId)
    }

    func clearDrafts(for sessionExerciseIds: [UUID]) {
        for id in sessionExerciseIds {
            draftsBySessionExerciseId.removeValue(forKey: id)
        }
    }
}
