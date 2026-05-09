import SwiftUI

struct ExerciseTransferToolView: View {
    private enum PickerKind: String, Identifiable {
        case source
        case target
        case sessions

        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var exerciseService: ExerciseService
    @EnvironmentObject private var sessionService: SessionService
    @EnvironmentObject private var sessionExerciseService: SessionExerciseService

    @State private var activePicker: PickerKind?
    @State private var selectedSourceExerciseId: UUID?
    @State private var selectedTargetExerciseId: UUID?
    @State private var selectedSessionIds: Set<UUID> = []

    @State private var showResultAlert = false
    @State private var resultTitle = ""
    @State private var resultMessage = ""
    @State private var didTransfer = false

    init(initialSourceExerciseId: UUID? = nil) {
        _selectedSourceExerciseId = State(initialValue: initialSourceExerciseId)
    }

    private var selectedSourceExercise: Exercise? {
        guard let selectedSourceExerciseId else { return nil }
        return exerciseService.exercises.first { $0.id == selectedSourceExerciseId }
    }

    private var selectedTargetExercise: Exercise? {
        guard let selectedTargetExerciseId else { return nil }
        return exerciseService.exercises.first { $0.id == selectedTargetExerciseId }
    }

    private var exerciseSessionCounts: [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for session in sessionService.sessions {
            let uniqueExerciseIds = Set(session.sessionEntries.map { $0.exercise.id })
            for id in uniqueExerciseIds {
                counts[id, default: 0] += 1
            }
        }
        return counts
    }

    private var sourceExercises: [Exercise] {
        exerciseService.exercises
            .filter { (exerciseSessionCounts[$0.id] ?? 0) > 0 }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var targetExercises: [Exercise] {
        guard let source = selectedSourceExercise else {
            return exerciseService.exercises.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
        return exerciseService.exercises
            .filter { $0.id != source.id }
            .filter { $0.type == source.type }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var sessionsWithSourceExercise: [Session] {
        guard let source = selectedSourceExercise else { return [] }
        return sessionService.sessions
            .filter { session in
                session.sessionEntries.contains(where: { $0.exercise.id == source.id })
            }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private var sourceSetCountsBySession: [UUID: Int] {
        guard let source = selectedSourceExercise else { return [:] }
        var result: [UUID: Int] = [:]
        for session in sessionsWithSourceExercise {
            let setCount = session.sessionEntries
                .filter { $0.exercise.id == source.id }
                .reduce(0) { $0 + $1.sets.count }
            result[session.id] = setCount
        }
        return result
    }

    private var canTransfer: Bool {
        selectedSourceExercise != nil &&
        selectedTargetExercise != nil &&
        !selectedSessionIds.isEmpty
    }

    private var canSwapSelections: Bool {
        guard let source = selectedSourceExercise, let target = selectedTargetExercise else { return false }
        guard source.type == target.type else { return false }
        return (exerciseSessionCounts[target.id] ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Text("Transfer exercise history between two exercises of the same type.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TransferSelectionCard(
                    title: "1) Source Exercise",
                    value: selectedSourceExercise?.name ?? "Select source",
                    subtitle: sourceSubtitle,
                    action: { activePicker = .source }
                )

                Button {
                    swapSelections()
                } label: {
                    Label("Swap", systemImage: "arrow.up.arrow.down")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .adaptiveCapsuleSurface()
                }
                .buttonStyle(.plain)
                .disabled(!canSwapSelections)
                .opacity(canSwapSelections ? 1.0 : 0.55)

                TransferSelectionCard(
                    title: "2) Target Exercise",
                    value: selectedTargetExercise?.name ?? "Select target",
                    subtitle: targetSubtitle,
                    action: { activePicker = .target }
                )
                .disabled(selectedSourceExercise == nil)
                .opacity(selectedSourceExercise == nil ? 0.55 : 1.0)

                TransferSelectionCard(
                    title: "3) Sessions",
                    value: selectedSessionIds.isEmpty ? "Select sessions" : "\(selectedSessionIds.count) selected",
                    subtitle: selectedSourceExercise == nil ? nil : "Only sessions containing source exercise",
                    action: { activePicker = .sessions }
                )
                .disabled(selectedSourceExercise == nil)
                .opacity(selectedSourceExercise == nil ? 0.55 : 1.0)

                Spacer()

                Button {
                    performTransfer()
                } label: {
                    Text("Transfer")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(canTransfer ? Color.accentColor : Color.gray.opacity(0.3))
                        .foregroundStyle(canTransfer ? Color.primary : Color.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canTransfer)
            }
            .padding(16)
            .navigationTitle("Transfer History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $activePicker) { picker in
                switch picker {
                case .source:
                    ExerciseSinglePickerSheet(
                        title: "Source Exercise",
                        prompt: "Search source",
                        exercises: sourceExercises,
                        selectedId: selectedSourceExerciseId
                    ) { exercise in
                        selectedSourceExerciseId = exercise.id
                        activePicker = nil
                    } sessionCountProvider: { exercise in
                        exerciseSessionCounts[exercise.id] ?? 0
                    }
                    .presentationDetents([.fraction(0.45), .medium, .large])
                    .presentationDragIndicator(.visible)
                case .target:
                    ExerciseSinglePickerSheet(
                        title: "Target Exercise",
                        prompt: "Search target",
                        exercises: targetExercises,
                        selectedId: selectedTargetExerciseId
                    ) { exercise in
                        selectedTargetExerciseId = exercise.id
                        activePicker = nil
                    } sessionCountProvider: { exercise in
                        exerciseSessionCounts[exercise.id] ?? 0
                    }
                    .presentationDetents([.fraction(0.45), .medium, .large])
                    .presentationDragIndicator(.visible)
                case .sessions:
                    SessionMultiPickerSheet(
                        sessions: sessionsWithSourceExercise,
                        selectedSessionIds: $selectedSessionIds,
                        setCountProvider: { session in
                            sourceSetCountsBySession[session.id] ?? 0
                        }
                    )
                    .presentationDetents([.fraction(0.5), .medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
            .onChange(of: selectedSourceExerciseId) { _, _ in
                if let source = selectedSourceExercise,
                   let target = selectedTargetExercise,
                   source.type == target.type,
                   source.id != target.id {
                    // Keep valid target when source changes.
                } else {
                    selectedTargetExerciseId = nil
                }
                selectedSessionIds.removeAll()
            }
            .alert(resultTitle, isPresented: $showResultAlert) {
                Button("OK") {
                    if didTransfer {
                        dismiss()
                    }
                }
            } message: {
                Text(resultMessage)
            }
        }
    }

    private func performTransfer() {
        guard let source = selectedSourceExercise, let target = selectedTargetExercise else { return }

        do {
            try sessionExerciseService.transferExerciseHistory(
                from: source,
                to: target,
                sessionIds: selectedSessionIds
            )
            sessionService.loadSessions()
            didTransfer = true
            resultTitle = "Transfer Complete"
            resultMessage = "Moved history across \(selectedSessionIds.count) session(s)."
            showResultAlert = true
        } catch {
            didTransfer = false
            resultTitle = "Transfer Failed"
            resultMessage = error.localizedDescription
            showResultAlert = true
        }
    }

    private var sourceSubtitle: String? {
        guard let source = selectedSourceExercise else { return nil }
        let count = exerciseSessionCounts[source.id] ?? 0
        return count > 0 ? "\(source.exerciseType.name) • \(count) sessions" : source.exerciseType.name
    }

    private var targetSubtitle: String? {
        guard let target = selectedTargetExercise else { return nil }
        let count = exerciseSessionCounts[target.id] ?? 0
        return count > 0 ? "\(target.exerciseType.name) • \(count) sessions" : target.exerciseType.name
    }

    private func swapSelections() {
        guard let sourceId = selectedSourceExerciseId, let targetId = selectedTargetExerciseId else { return }
        selectedSourceExerciseId = targetId
        selectedTargetExerciseId = sourceId
        selectedSessionIds.removeAll()
    }
}

private struct TransferSelectionCard: View {
    let title: String
    let value: String
    let subtitle: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(value)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .adaptiveCardSurface(cornerRadius: 12)
        }
        .buttonStyle(.plain)
    }
}

private struct ExerciseSinglePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let prompt: String
    let exercises: [Exercise]
    let selectedId: UUID?
    let onPick: (Exercise) -> Void
    let sessionCountProvider: (Exercise) -> Int

    @State private var searchText = ""

    private var filteredExercises: [Exercise] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return exercises }
        return exercises.filter { exercise in
            if exercise.name.localizedCaseInsensitiveContains(query) {
                return true
            }
            return (exercise.aliases ?? []).contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredExercises, id: \.id) { exercise in
                    Button {
                        onPick(exercise)
                    } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name)
                                    .foregroundStyle(.primary)
                                Text(exerciseSubtitle(exercise))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedId == exercise.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .cardListRowContentPadding()
                    }
                    .buttonStyle(.plain)
                    .cardListRowStyle()
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .screenListContentFrame()
            .appBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: prompt)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func exerciseSubtitle(_ exercise: Exercise) -> String {
        let count = sessionCountProvider(exercise)
        if count > 0 {
            return "\(exercise.exerciseType.name) • \(count) sessions"
        }
        return exercise.exerciseType.name
    }
}

private struct SessionMultiPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let sessions: [Session]
    @Binding var selectedSessionIds: Set<UUID>
    let setCountProvider: (Session) -> Int

    @State private var searchText = ""

    private var filteredSessions: [Session] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sessions }

        return sessions.filter { session in
            let dateString = session.timestamp.formatted(date: .abbreviated, time: .shortened)
            if dateString.localizedCaseInsensitiveContains(query) {
                return true
            }
            if session.notes.localizedCaseInsensitiveContains(query) {
                return true
            }
            return session.sessionEntries.contains { entry in
                entry.exercise.name.localizedCaseInsensitiveContains(query)
            }
        }
    }

    private var allSelected: Bool {
        !sessions.isEmpty && selectedSessionIds.count == sessions.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(allSelected ? "Clear All" : "Select All") {
                        if allSelected {
                            selectedSessionIds.removeAll()
                        } else {
                            selectedSessionIds = Set(sessions.map(\.id))
                        }
                    }
                    .fontWeight(.semibold)
                    .cardListRowContentPadding()
                    .cardListRowStyle()
                }

                Section {
                    if filteredSessions.isEmpty {
                        Text("No sessions found")
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(filteredSessions, id: \.id) { session in
                            Button {
                                toggleSelection(session.id)
                            } label: {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(session.timestamp.formatted(date: .abbreviated, time: .shortened))
                                            .foregroundStyle(.primary)
                                        let setCount = setCountProvider(session)
                                        Text("\(setCount) set\(setCount == 1 ? "" : "s")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if !session.notes.isEmpty {
                                            Text(session.notes)
                                                .font(.caption)
                                                .lineLimit(1)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: selectedSessionIds.contains(session.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedSessionIds.contains(session.id) ? .accentColor : .secondary)
                                }
                                .cardListRowContentPadding()
                            }
                            .buttonStyle(.plain)
                            .cardListRowStyle()
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .screenListContentFrame()
            .appBackground()
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search sessions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func toggleSelection(_ sessionId: UUID) {
        if selectedSessionIds.contains(sessionId) {
            selectedSessionIds.remove(sessionId)
        } else {
            selectedSessionIds.insert(sessionId)
        }
    }
}
