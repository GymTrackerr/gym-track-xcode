import Foundation
import SwiftData
import Combine

@MainActor
final class NotesImportViewModel: ObservableObject {
    enum RoutineResolutionMode: String, CaseIterable, Identifiable {
        case matched
        case existing
        case createNew
        case none

        var id: String { rawValue }

        var title: String {
            switch self {
            case .matched:
                return "Matched"
            case .existing:
                return "Existing"
            case .createNew:
                return "Create"
            case .none:
                return "None"
            }
        }
    }

    enum ExerciseResolutionMode: String, CaseIterable, Identifiable {
        case existing
        case createNew

        var id: String { rawValue }

        var title: String {
            switch self {
            case .existing:
                return "Existing"
            case .createNew:
                return "Create"
            }
        }
    }

    struct ExerciseSelection {
        var mode: ExerciseResolutionMode = .existing
        var selectedExerciseId: UUID?
        var newExerciseName: String = ""
        var rememberAlias: Bool = false
    }

    struct ResolutionState {
        var routineMode: RoutineResolutionMode = .matched
        var selectedRoutineId: UUID?
        var newRoutineName: String = ""
        var rememberRoutineAlias: Bool = false

        var routineCandidates: [Routine] = []
        var exerciseCandidates: [String: [Exercise]] = [:]
        var exerciseSelections: [String: ExerciseSelection] = [:]
        var unresolvedExercises: [String] = []

        var duplicateExists: Bool = false
        var allowDuplicateImport: Bool = false

        var statusMessage: String?
        var errorMessage: String?

        static let empty = ResolutionState()
    }

    @Published var rawInput: String = ""
    @Published var defaultWeightUnit: WeightUnit = .lb

    @Published var batch: NotesImportBatch = NotesImportBatch(drafts: [])
    @Published var currentDraftIndex: Int = 0
    @Published var resolutionState: ResolutionState = .empty

    @Published var selectedDateForCurrentDraft: Date = Date()

    @Published var showDuplicatePrompt: Bool = false
    @Published var isCommitting: Bool = false

    var hasDrafts: Bool {
        !batch.drafts.isEmpty
    }

    var currentDraft: NotesImportDraft? {
        guard batch.drafts.indices.contains(currentDraftIndex) else { return nil }
        return batch.drafts[currentDraftIndex]
    }

    private var modelContext: ModelContext?
    private var currentUserId: UUID?

    private let parser = NotesImportParser()
    private let resolver = NotesImportResolver()
    private let writer = NotesImportWriterService()

    func configure(context: ModelContext, currentUserId: UUID?) {
        self.modelContext = context
        self.currentUserId = currentUserId
    }

    func parseInput(text: String) {
        rawInput = text

        let parsed = parser.parseBatch(from: text, defaultWeightUnit: defaultWeightUnit)
        batch = parsed
        currentDraftIndex = 0

        resolutionState = .empty
        showDuplicatePrompt = false

        if let draft = currentDraft {
            selectedDateForCurrentDraft = draft.parsedDate ?? Date()
        }

        resolveRoutine()
        resolveExercise()
        refreshDuplicateState()
    }

    func moveToNextDraft() {
        guard batch.drafts.indices.contains(currentDraftIndex + 1) else { return }
        currentDraftIndex += 1
        onCurrentDraftChanged()
    }

    func moveToPreviousDraft() {
        guard currentDraftIndex > 0 else { return }
        currentDraftIndex -= 1
        onCurrentDraftChanged()
    }

    func setCurrentDraftIndex(_ index: Int) {
        guard batch.drafts.indices.contains(index) else { return }
        currentDraftIndex = index
        onCurrentDraftChanged()
    }

    func applySelectedDateToCurrentDraft() {
        guard var draft = currentDraft else { return }
        draft.parsedDate = selectedDateForCurrentDraft
        batch.drafts[currentDraftIndex] = draft
        resolutionState.errorMessage = nil
    }

    func resolveRoutine() {
        guard let context = modelContext else {
            resolutionState.errorMessage = "Missing model context."
            return
        }

        guard let userId = currentUserId else {
            resolutionState.routineCandidates = []
            return
        }

        do {
            let descriptor = FetchDescriptor<Routine>(
                predicate: #Predicate<Routine> { routine in
                    routine.user_id == userId
                },
                sortBy: [SortDescriptor(\.name)]
            )
            let routines = try context.fetch(descriptor)
            resolutionState.routineCandidates = routines

            let matched = try resolver.resolveRoutine(
                routineNameRaw: currentDraft?.routineNameRaw,
                userId: userId,
                context: context
            )

            if let matched {
                resolutionState.routineMode = .matched
                resolutionState.selectedRoutineId = matched.id
            } else if let first = routines.first {
                resolutionState.routineMode = .existing
                resolutionState.selectedRoutineId = first.id
            } else {
                resolutionState.routineMode = .none
                resolutionState.selectedRoutineId = nil
            }
        } catch {
            resolutionState.errorMessage = "Routine resolution failed: \(error.localizedDescription)"
        }
    }

    func resolveExercise() {
        guard let context = modelContext else {
            resolutionState.errorMessage = "Missing model context."
            return
        }

        guard let userId = currentUserId else {
            resolutionState.exerciseCandidates = [:]
            return
        }

        guard let draft = currentDraft else {
            resolutionState.exerciseCandidates = [:]
            return
        }

        let rawExerciseNames = rawExerciseNames(from: draft)

        do {
            let resolved = try resolver.resolveExercises(
                rawNames: rawExerciseNames,
                userId: userId,
                context: context
            )

            var candidates: [String: [Exercise]] = [:]
            var selections: [String: ExerciseSelection] = [:]
            var unresolved: [String] = []

            for rawName in rawExerciseNames {
                let entry = resolved[rawName]
                let entryCandidates = entry?.candidates ?? []
                candidates[rawName] = entryCandidates

                if let matched = entry?.resolved {
                    selections[rawName] = ExerciseSelection(
                        mode: .existing,
                        selectedExerciseId: matched.id,
                        newExerciseName: rawName,
                        rememberAlias: false
                    )
                } else {
                    unresolved.append(rawName)
                    selections[rawName] = ExerciseSelection(
                        mode: .createNew,
                        selectedExerciseId: entryCandidates.first?.id,
                        newExerciseName: rawName,
                        rememberAlias: false
                    )
                }
            }

            resolutionState.exerciseCandidates = candidates
            resolutionState.exerciseSelections = selections
            resolutionState.unresolvedExercises = unresolved
            resolutionState.errorMessage = nil
        } catch {
            resolutionState.errorMessage = "Exercise resolution failed: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func confirmImport() -> Bool {
        guard let context = modelContext else {
            resolutionState.errorMessage = "Missing model context."
            return false
        }

        guard let userId = currentUserId else {
            resolutionState.errorMessage = "No active user. Commit is blocked until currentUserId exists."
            return false
        }

        guard var draft = currentDraft else {
            resolutionState.errorMessage = "No draft selected."
            return false
        }

        if draft.parsedDate == nil {
            draft.parsedDate = selectedDateForCurrentDraft
            batch.drafts[currentDraftIndex] = draft
        }

        do {
            if try writer.duplicateExists(draft: draft, userId: userId, context: context), !resolutionState.allowDuplicateImport {
                resolutionState.duplicateExists = true
                showDuplicatePrompt = true
                return false
            }

            let resolved = try buildResolutionResult(for: draft, userId: userId, context: context)
            isCommitting = true
            defer { isCommitting = false }

            _ = try writer.commit(
                draft: draft,
                resolution: resolved,
                userId: userId,
                context: context,
                defaultWeightUnit: defaultWeightUnit
            )

            resolutionState.statusMessage = "Draft imported successfully."
            resolutionState.errorMessage = nil
            resolutionState.allowDuplicateImport = false
            showDuplicatePrompt = false
            refreshDuplicateState()
            return true
        } catch {
            resolutionState.errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func importDuplicateAnyway() -> Bool {
        resolutionState.allowDuplicateImport = true
        return confirmImport()
    }
}

private extension NotesImportViewModel {
    func onCurrentDraftChanged() {
        if let draft = currentDraft {
            selectedDateForCurrentDraft = draft.parsedDate ?? Date()
        }

        resolutionState.errorMessage = nil
        resolutionState.statusMessage = nil
        resolutionState.allowDuplicateImport = false
        showDuplicatePrompt = false

        resolveRoutine()
        resolveExercise()
        refreshDuplicateState()
    }

    func refreshDuplicateState() {
        guard let context = modelContext,
              let userId = currentUserId,
              let draft = currentDraft else {
            resolutionState.duplicateExists = false
            return
        }

        do {
            resolutionState.duplicateExists = try writer.duplicateExists(
                draft: draft,
                userId: userId,
                context: context
            )
        } catch {
            resolutionState.errorMessage = "Duplicate check failed: \(error.localizedDescription)"
        }
    }

    func rawExerciseNames(from draft: NotesImportDraft) -> [String] {
        var names: [String] = []
        var seen: Set<String> = []

        for item in draft.items {
            let rawName: String
            switch item {
            case .strength(let strength):
                rawName = strength.exerciseNameRaw
            case .cardio(let cardio):
                rawName = cardio.exerciseNameRaw
            }

            let key = normalize(rawName)
            if !key.isEmpty && seen.insert(key).inserted {
                names.append(rawName.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        return names
    }

    func buildResolutionResult(
        for draft: NotesImportDraft,
        userId: UUID,
        context: ModelContext
    ) throws -> ResolutionResult {
        var resolvedRoutine: Routine?

        switch resolutionState.routineMode {
        case .none:
            resolvedRoutine = nil

        case .matched, .existing:
            if let routineId = resolutionState.selectedRoutineId {
                resolvedRoutine = resolutionState.routineCandidates.first(where: { $0.id == routineId })
            }

        case .createNew:
            let name = resolutionState.newRoutineName.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalName = name.isEmpty ? (draft.routineNameRaw ?? "Imported Routine") : name

            let nextOrder = (resolutionState.routineCandidates.map(\.order).max() ?? -1) + 1
            let newRoutine = Routine(order: nextOrder, name: finalName, user_id: userId)

            if let alias = draft.routineNameRaw {
                _ = resolver.addRoutineAliasIfNeeded(
                    routine: newRoutine,
                    aliasRaw: alias,
                    rememberAlias: resolutionState.rememberRoutineAlias
                )
            }

            context.insert(newRoutine)
            resolvedRoutine = newRoutine
        }

        var resolvedExercises: [String: Exercise] = [:]
        var unresolvedExercises: [String] = []

        for rawName in rawExerciseNames(from: draft) {
            guard let selection = resolutionState.exerciseSelections[rawName] else {
                unresolvedExercises.append(rawName)
                continue
            }

            switch selection.mode {
            case .existing:
                guard let selectedId = selection.selectedExerciseId,
                      let selected = resolutionState.exerciseCandidates[rawName]?.first(where: { $0.id == selectedId }) else {
                    unresolvedExercises.append(rawName)
                    continue
                }

                _ = resolver.addExerciseAliasIfNeeded(
                    exercise: selected,
                    aliasRaw: rawName,
                    rememberAlias: selection.rememberAlias
                )

                resolvedExercises[rawName] = selected

            case .createNew:
                let trimmed = selection.newExerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
                let exerciseName = trimmed.isEmpty ? rawName : trimmed
                let newExercise = Exercise(
                    name: exerciseName,
                    type: inferredExerciseType(from: rawName),
                    user_id: userId,
                    isUserCreated: true
                )

                context.insert(newExercise)
                resolvedExercises[rawName] = newExercise
            }
        }

        return ResolutionResult(
            resolvedRoutine: resolvedRoutine,
            resolvedExercises: resolvedExercises,
            unresolvedExercises: unresolvedExercises
        )
    }

    func inferredExerciseType(from rawName: String) -> ExerciseType {
        let lower = rawName.lowercased()
        if lower.contains("run") || lower.contains("treadmill") || lower.contains("jog") {
            return .run
        }
        if lower.contains("bike") || lower.contains("cycle") {
            return .bike
        }
        if lower.contains("swim") {
            return .swim
        }
        return .weight
    }

    func normalize(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
