import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct NotesImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel = NotesImportViewModel()
    @State private var exercisePickerRawName: String?
    @State private var draftDecisions: [Int: DraftDecision] = [:]

    let currentUserId: UUID?
    var onImportCompleted: (() -> Void)? = nil

    var body: some View {
        Group {
            if viewModel.hasDrafts {
                previewScreen
            } else {
                pasteScreen
            }
        }
        .navigationTitle("Import from Notes")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.configure(context: modelContext, currentUserId: currentUserId)
        }
        .alert("Duplicate Session Detected", isPresented: $viewModel.showDuplicatePrompt) {
            Button("Cancel", role: .cancel) { }
            Button("Import Anyway") {
                if viewModel.importDuplicateAnyway() {
                    markCurrentDraftConfirmedAndAdvance()
                }
            }
        } message: {
            Text("Seems like this session was already imported. Import anyway?")
        }
        .sheet(
            isPresented: Binding(
                get: { exercisePickerRawName != nil },
                set: { isPresented in
                    if !isPresented {
                        exercisePickerRawName = nil
                    }
                }
            )
        ) {
            if let rawName = exercisePickerRawName {
                NotesImportExercisePickerView(viewModel: viewModel, rawName: rawName)
            }
        }
    }

    private var pasteScreen: some View {
        VStack(spacing: 16) {
            Text("Paste one or more sessions from Notes, choose the default weight unit, then parse.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Default Unit", selection: $viewModel.defaultWeightUnit) {
                ForEach(WeightUnit.allCases) { unit in
                    Text(unit.name.uppercased()).tag(unit)
                }
            }
            .pickerStyle(.segmented)

            TextEditor(text: $viewModel.rawInput)
                .frame(minHeight: 220)
                .padding(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            Button {
                pasteFromClipboard()
            } label: {
                Label("Paste", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                viewModel.parseInput(text: viewModel.rawInput)
            } label: {
                Text("Parse")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()
        }
        .padding()
    }

    private var previewScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                draftNavigator

                if let draft = viewModel.currentDraft {
                    draftHeader(draft)
                    routineSection(draft)
                    exerciseResolutionSection(draft)
                    parsedItemsSection(draft)
                    warningsSection(draft)
                    actionsSection
                }
            }
            .padding()
        }
    }

    private var draftNavigator: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Draft")
                .font(.headline)

            Picker("Draft", selection: Binding(
                get: { viewModel.currentDraftIndex },
                set: { viewModel.setCurrentDraftIndex($0) }
            )) {
                ForEach(Array(viewModel.batch.drafts.indices), id: \.self) { index in
                    Text("\(index + 1)").tag(index)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Button("Previous") {
                    viewModel.moveToPreviousDraft()
                }
                .disabled(viewModel.currentDraftIndex == 0)

                Spacer()

                Button("Next") {
                    viewModel.moveToNextDraft()
                }
                .disabled(viewModel.currentDraftIndex >= viewModel.batch.drafts.count - 1)
            }
            .font(.footnote)

            HStack(spacing: 10) {
                Button {
                    confirmCurrentDraft()
                } label: {
                    if viewModel.isCommitting {
                        ProgressView()
                    } else {
                        Text("Confirm This Import")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    currentDraftDecision != nil
                    || viewModel.isCommitting
                    || !viewModel.canConfirmCurrentDraft
                )

                Button("Deny This Import", role: .destructive) {
                    denyCurrentDraft()
                }
                .buttonStyle(.bordered)
                .disabled(currentDraftDecision != nil || viewModel.isCommitting)
            }

            if let decision = currentDraftDecision {
                Text("Decision: \(decision.title)")
                    .font(.footnote)
                    .foregroundStyle(decision.color)
            } else {
                Text("Decision: Pending")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func draftHeader(_ draft: NotesImportDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Header")
                .font(.headline)

            Text("Routine: \(draft.routineNameRaw ?? "(none)")")
            Text("Date: \(dateText(draft.parsedDate))")
            Text("Start: \(dateText(draft.startTime))")
            Text("End: \(dateText(draft.endTime))")

            dateTimeResolverSection(draft)

            if viewModel.resolutionState.duplicateExists {
                Text("Potential duplicate detected for this user.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func routineSection(_ draft: NotesImportDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Routine Resolution")
                .font(.headline)

            Picker("Routine", selection: $viewModel.resolutionState.routineMode) {
                ForEach(NotesImportViewModel.RoutineResolutionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            switch viewModel.resolutionState.routineMode {
            case .matched, .existing:
                Picker(
                    "Existing Routine",
                    selection: Binding(
                        get: { viewModel.resolutionState.selectedRoutineId },
                        set: { viewModel.resolutionState.selectedRoutineId = $0 }
                    )
                ) {
                    Text("None").tag(UUID?.none)
                    ForEach(viewModel.resolutionState.routineCandidates, id: \.id) { routine in
                        Text(routine.name).tag(Optional(routine.id))
                    }
                }

                if viewModel.resolutionState.routineMode == .existing, draft.routineNameRaw != nil {
                    Toggle(
                        "Remember header as routine alias",
                        isOn: $viewModel.resolutionState.rememberRoutineAlias
                    )
                }

            case .createNew:
                TextField(
                    "New routine name",
                    text: $viewModel.resolutionState.newRoutineName
                )
                .textFieldStyle(.roundedBorder)

                if draft.routineNameRaw != nil {
                    Toggle(
                        "Remember header as routine alias",
                        isOn: $viewModel.resolutionState.rememberRoutineAlias
                    )
                }

            case .none:
                Text("Session will be imported without a routine.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func exerciseResolutionSection(_ draft: NotesImportDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exercise Resolution")
                .font(.headline)

            if viewModel.resolutionState.exerciseSelections.isEmpty {
                Text("No parsed exercises.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(exerciseNames(from: draft), id: \.self) { rawName in
                if let selection = viewModel.resolutionState.exerciseSelections[rawName] {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(rawName)
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Picker(
                            "Mode",
                            selection: Binding(
                                get: { selection.mode },
                                set: { viewModel.resolutionState.exerciseSelections[rawName]?.mode = $0 }
                            )
                        ) {
                            ForEach(availableExerciseModes(for: rawName, selection: selection)) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        switch selection.mode {
                        case .matched:
                            Text("Matched: \(viewModel.selectedExercise(for: rawName)?.name ?? "Unknown")")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if let matchedExercise = viewModel.selectedExercise(for: rawName) {
                                NavigationLink("View Exercise Details") {
                                    SingleExerciseView(exercise: matchedExercise)
                                }
                                .font(.footnote)
                            }
                        case .existing:
                            Button("Choose Exercise…") {
                                exercisePickerRawName = rawName
                            }
                            .buttonStyle(.bordered)

                            Text("Selected: \(viewModel.selectedExercise(for: rawName)?.name ?? "None")")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if let selectedExercise = viewModel.selectedExercise(for: rawName) {
                                NavigationLink("View Exercise Details") {
                                    SingleExerciseView(exercise: selectedExercise)
                                }
                                .font(.footnote)
                            }

                            Toggle(
                                "Remember alias for this exercise",
                                isOn: Binding(
                                    get: { viewModel.resolutionState.exerciseSelections[rawName]?.rememberAlias ?? false },
                                    set: { viewModel.resolutionState.exerciseSelections[rawName]?.rememberAlias = $0 }
                                )
                            )
                        case .createNew:
                            TextField(
                                "Create exercise name",
                                text: Binding(
                                    get: { viewModel.resolutionState.exerciseSelections[rawName]?.newExerciseName ?? rawName },
                                    set: { viewModel.resolutionState.exerciseSelections[rawName]?.newExerciseName = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func parsedItemsSection(_ draft: NotesImportDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Parsed Items")
                .font(.headline)

            ForEach(Array(draft.items.enumerated()), id: \.offset) { index, item in
                switch item {
                case .strength(let strength):
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(index + 1). Strength: \(strength.exerciseNameRaw)")
                            .font(.footnote)
                            .fontWeight(.semibold)

                        ForEach(Array(strength.sets.enumerated()), id: \.offset) { setIndex, set in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Set \(setIndex + 1): \(setDescription(set))")
                                    .font(.footnote)
                                if let details = perSideDescription(set) {
                                    Text(details)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if let notes = strength.notes, !notes.isEmpty {
                            Text("Note: \(notes)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                case .cardio(let cardio):
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(index + 1). Cardio: \(cardio.exerciseNameRaw)")
                            .font(.footnote)
                            .fontWeight(.semibold)

                        ForEach(Array(cardio.sets.enumerated()), id: \.offset) { setIndex, set in
                            Text("Set \(setIndex + 1): \(cardioSetDescription(set))")
                                .font(.footnote)
                        }

                        if let notes = cardio.notes, !notes.isEmpty {
                            Text("Telemetry: \(notes)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func warningsSection(_ draft: NotesImportDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !draft.warnings.isEmpty {
                Text("Warnings")
                    .font(.headline)

                ForEach(draft.warnings, id: \.self) { warning in
                    Text("• \(warning)")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            if !draft.unknownLines.isEmpty {
                Text("Unknown Lines")
                    .font(.headline)

                ForEach(draft.unknownLines, id: \.self) { line in
                    Text("• \(line)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = viewModel.resolutionState.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let status = viewModel.resolutionState.statusMessage {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 10) {
            Button("Re-Resolve") {
                viewModel.resolveRoutine()
                viewModel.resolveExercise()
            }
            .buttonStyle(.bordered)

            Button("Back to Paste") {
                viewModel.batch = NotesImportBatch(drafts: [])
                viewModel.currentDraftIndex = 0
                viewModel.resolutionState = .empty
                draftDecisions = [:]
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func dateTimeResolverSection(_ draft: NotesImportDraft) -> some View {
        let validationMessage = viewModel.dateTimeValidationMessage(for: viewModel.currentDraftIndex)
        let needsDateResolution = draft.parsedDate == nil
        let needsTimeResolution = draft.startTime == nil || draft.endTime == nil

        if needsDateResolution || needsTimeResolution {
            VStack(alignment: .leading, spacing: 8) {
                Text("Resolve Date & Time")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if needsDateResolution {
                    DatePicker(
                        "Session Date",
                        selection: $viewModel.selectedDateForCurrentDraft,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)

                    Button("Use This Date") {
                        viewModel.applySelectedDateToCurrentDraft()
                    }
                    .buttonStyle(.bordered)
                }

                DatePicker(
                    "Start",
                    selection: Binding(
                        get: { viewModel.selectedStartForCurrentDraft },
                        set: { viewModel.setResolvedStart($0) }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)

                DatePicker(
                    "End",
                    selection: Binding(
                        get: { viewModel.selectedEndForCurrentDraft },
                        set: { viewModel.setResolvedEnd($0) }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)

                if needsTimeResolution {
                    Button("Use Suggested Time Range") {
                        viewModel.useSuggestedTimeRangeForCurrentDraft()
                    }
                    .buttonStyle(.bordered)
                }

                if let validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "(missing)" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func pasteFromClipboard() {
#if os(iOS)
        if let clipboardText = UIPasteboard.general.string {
            viewModel.rawInput = clipboardText
        }
#elseif os(macOS)
        if let clipboardText = NSPasteboard.general.string(forType: .string) {
            viewModel.rawInput = clipboardText
        }
#endif
    }

    private func exerciseNames(from draft: NotesImportDraft) -> [String] {
        var names: [String] = []
        for item in draft.items {
            switch item {
            case .strength(let strength):
                if !names.contains(strength.exerciseNameRaw) {
                    names.append(strength.exerciseNameRaw)
                }
            case .cardio(let cardio):
                if !names.contains(cardio.exerciseNameRaw) {
                    names.append(cardio.exerciseNameRaw)
                }
            }
        }
        return names
    }

    private func availableExerciseModes(
        for rawName: String,
        selection: NotesImportViewModel.ExerciseSelection
    ) -> [NotesImportViewModel.ExerciseResolutionMode] {
        let hasMatchedSelection = (selection.selectedExerciseId != nil)
            && (viewModel.resolutionState.exerciseCandidates[rawName]?.contains(where: { $0.id == selection.selectedExerciseId }) ?? false)

        if hasMatchedSelection {
            return NotesImportViewModel.ExerciseResolutionMode.allCases
        }

        return [.existing, .createNew]
    }

    private func setDescription(_ set: ParsedStrengthSet) -> String {
        let weightText: String
        if let weight = set.weight {
            weightText = "\(formattedNumber(weight)) \(set.weightUnit.name)"
        } else {
            weightText = "bodyweight"
        }

        var parts: [String] = ["\(set.reps)x @ \(weightText)"]
        if let restSeconds = set.restSeconds {
            parts.append("rest \(restSeconds)s")
        }
        return parts.joined(separator: ", ")
    }

    private func perSideDescription(_ set: ParsedStrengthSet) -> String? {
        guard set.isPerSide else { return nil }
        guard let base = set.baseWeight, let perSide = set.perSideWeight else { return nil }
        return "Base \(formattedNumber(base)) + per-side \(formattedNumber(perSide))"
    }

    private func cardioSetDescription(_ set: ParsedCardioSet) -> String {
        var parts: [String] = []
        if let duration = set.durationSeconds {
            parts.append("duration \(duration)s")
        }
        if let distance = set.distance {
            parts.append("distance \(formattedNumber(distance)) \(set.distanceUnit.rawValue)")
        }
        if let pace = set.paceSeconds {
            parts.append("pace \(pace)s")
        }
        if parts.isEmpty {
            return "no cardio metrics parsed"
        }
        return parts.joined(separator: ", ")
    }

    private func formattedNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    private var currentDraftDecision: DraftDecision? {
        draftDecisions[viewModel.currentDraftIndex]
    }

    private func confirmCurrentDraft() {
        guard viewModel.confirmImport() else { return }
        markCurrentDraftConfirmedAndAdvance()
    }

    private func markCurrentDraftConfirmedAndAdvance() {
        draftDecisions[viewModel.currentDraftIndex] = .confirmed
        advanceOrFinishReview()
    }

    private func denyCurrentDraft() {
        draftDecisions[viewModel.currentDraftIndex] = .denied
        advanceOrFinishReview()
    }

    private func advanceOrFinishReview() {
        if let nextIndex = nextPendingDraftIndex(after: viewModel.currentDraftIndex) {
            viewModel.setCurrentDraftIndex(nextIndex)
            return
        }

        if let firstPending = nextPendingDraftIndex(after: -1) {
            viewModel.setCurrentDraftIndex(firstPending)
            return
        }

        if draftDecisions.values.contains(.confirmed) {
            onImportCompleted?()
        }
        dismiss()
    }

    private func nextPendingDraftIndex(after index: Int) -> Int? {
        for candidate in (index + 1)..<viewModel.batch.drafts.count {
            if draftDecisions[candidate] == nil {
                return candidate
            }
        }
        return nil
    }
}

private enum DraftDecision: Equatable {
    case confirmed
    case denied

    var title: String {
        switch self {
        case .confirmed:
            return "Confirmed"
        case .denied:
            return "Denied"
        }
    }

    var color: Color {
        switch self {
        case .confirmed:
            return .green
        case .denied:
            return .red
        }
    }
}
