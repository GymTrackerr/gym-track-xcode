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
        .navigationTitle(Text(LocalizedStringResource("sessions.import.title", defaultValue: "Import from Notes", table: "Sessions")))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.configure(context: modelContext, currentUserId: currentUserId)
        }
        .alert(Text(LocalizedStringResource("sessions.import.duplicate.title", defaultValue: "Duplicate Session Detected", table: "Sessions")), isPresented: $viewModel.showDuplicatePrompt) {
            Button(role: .cancel) { } label: {
                Text(LocalizedStringResource("sessions.action.cancel", defaultValue: "Cancel", table: "Sessions"))
            }
            Button {
                if viewModel.importDuplicateAnyway() {
                    markCurrentDraftConfirmedAndAdvance()
                }
            } label: {
                Text(LocalizedStringResource("sessions.import.duplicate.importAnyway", defaultValue: "Import Anyway", table: "Sessions"))
            }
        } message: {
            Text(LocalizedStringResource("sessions.import.duplicate.message", defaultValue: "Seems like this session was already imported. Import anyway?", table: "Sessions"))
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
            Text(LocalizedStringResource("sessions.import.paste.instructions", defaultValue: "Paste one or more sessions from Notes, choose the default weight unit, then parse.", table: "Sessions"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker(LocalizedStringResource("sessions.import.defaultUnit", defaultValue: "Default Unit", table: "Sessions"), selection: $viewModel.defaultWeightUnit) {
                ForEach(WeightUnit.allCases) { unit in
                    Text(verbatim: unit.name.uppercased()).tag(unit)
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
                pasteFromClipboardAdding()
            } label: {
                Label {
                    Text(LocalizedStringResource("sessions.import.paste.add", defaultValue: "Paste Add", table: "Sessions"))
                } icon: {
                    Image(systemName: "plus.doc.on.clipboard")
                }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button(role: .destructive) {
                pasteFromClipboardReplacing()
            } label: {
                Label {
                    Text(LocalizedStringResource("sessions.import.paste.replace", defaultValue: "Paste Replace", table: "Sessions"))
                } icon: {
                    Image(systemName: "doc.on.clipboard")
                }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                viewModel.parseInput(text: viewModel.rawInput)
            } label: {
                Text(LocalizedStringResource("sessions.import.parse", defaultValue: "Parse", table: "Sessions"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()
        }
        .screenContentPadding()
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
            .screenContentPadding()
        }
    }

    private var draftNavigator: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringResource("sessions.import.draft.title", defaultValue: "Draft", table: "Sessions"))
                .font(.headline)

            Picker(LocalizedStringResource("sessions.import.draft.picker", defaultValue: "Draft", table: "Sessions"), selection: Binding(
                get: { viewModel.currentDraftIndex },
                set: { viewModel.setCurrentDraftIndex($0) }
            )) {
                ForEach(Array(viewModel.batch.drafts.indices), id: \.self) { index in
                    Text("\(index + 1)").tag(index)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Button {
                    viewModel.moveToPreviousDraft()
                } label: {
                    Text(LocalizedStringResource("sessions.import.draft.previous", defaultValue: "Previous", table: "Sessions"))
                }
                .disabled(viewModel.currentDraftIndex == 0)

                Spacer()

                Button {
                    viewModel.moveToNextDraft()
                } label: {
                    Text(LocalizedStringResource("sessions.import.draft.next", defaultValue: "Next", table: "Sessions"))
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
                        Text(LocalizedStringResource("sessions.import.confirmCurrent", defaultValue: "Confirm This Import", table: "Sessions"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    currentDraftDecision != nil
                    || viewModel.isCommitting
                    || !viewModel.canConfirmCurrentDraft
                )

                Button(role: .destructive) {
                    denyCurrentDraft()
                } label: {
                    Text(LocalizedStringResource("sessions.import.denyCurrent", defaultValue: "Deny This Import", table: "Sessions"))
                }
                .buttonStyle(.bordered)
                .disabled(currentDraftDecision != nil || viewModel.isCommitting)
            }

            if let decision = currentDraftDecision {
                Text(LocalizedStringResource("sessions.import.decision.value", defaultValue: "Decision: \(decision.titleText)", table: "Sessions"))
                    .font(.footnote)
                    .foregroundStyle(decision.color)
            } else {
                Text(LocalizedStringResource("sessions.import.decision.pending", defaultValue: "Decision: Pending", table: "Sessions"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func draftHeader(_ draft: NotesImportDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringResource("sessions.import.header.title", defaultValue: "Header", table: "Sessions"))
                .font(.headline)

            Text(LocalizedStringResource("sessions.import.header.routine", defaultValue: "Routine: \(draft.routineNameRaw ?? noneText)", table: "Sessions"))
            Text(LocalizedStringResource("sessions.import.header.date", defaultValue: "Date: \(dateText(draft.parsedDate))", table: "Sessions"))
            Text(LocalizedStringResource("sessions.import.header.start", defaultValue: "Start: \(dateText(draft.startTime))", table: "Sessions"))
            Text(LocalizedStringResource("sessions.import.header.end", defaultValue: "End: \(dateText(draft.endTime))", table: "Sessions"))

            dateTimeResolverSection(draft)

            if viewModel.resolutionState.duplicateExists {
                Text(LocalizedStringResource("sessions.import.duplicate.inline", defaultValue: "Potential duplicate detected for this user.", table: "Sessions"))
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func routineSection(_ draft: NotesImportDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringResource("sessions.import.routineResolution.title", defaultValue: "Routine Resolution", table: "Sessions"))
                .font(.headline)

            Picker(LocalizedStringResource("sessions.import.routineResolution.picker", defaultValue: "Routine", table: "Sessions"), selection: $viewModel.resolutionState.routineMode) {
                ForEach(NotesImportViewModel.RoutineResolutionMode.allCases) { mode in
                    Text(mode.titleResource).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            switch viewModel.resolutionState.routineMode {
            case .matched, .existing:
                Picker(
                    LocalizedStringResource("sessions.import.routineResolution.existingRoutine", defaultValue: "Existing Routine", table: "Sessions"),
                    selection: Binding(
                        get: { viewModel.resolutionState.selectedRoutineId },
                        set: { viewModel.resolutionState.selectedRoutineId = $0 }
                    )
                ) {
                    Text(LocalizedStringResource("sessions.value.none", defaultValue: "None", table: "Sessions")).tag(UUID?.none)
                    ForEach(viewModel.resolutionState.routineCandidates, id: \.id) { routine in
                        Text(verbatim: routine.name).tag(Optional(routine.id))
                    }
                }

                if viewModel.resolutionState.routineMode == .existing, draft.routineNameRaw != nil {
                    Toggle(
                        LocalizedStringResource("sessions.import.routineResolution.rememberAlias", defaultValue: "Remember header as routine alias", table: "Sessions"),
                        isOn: $viewModel.resolutionState.rememberRoutineAlias
                    )
                }

            case .createNew:
                TextField(
                    text: $viewModel.resolutionState.newRoutineName,
                    prompt: Text(LocalizedStringResource("sessions.import.routineResolution.newRoutineName", defaultValue: "New routine name", table: "Sessions"))
                ) {
                    Text(LocalizedStringResource("sessions.import.routineResolution.newRoutineNameLabel", defaultValue: "New routine name", table: "Sessions"))
                }
                .textFieldStyle(.roundedBorder)

                if draft.routineNameRaw != nil {
                    Toggle(
                        LocalizedStringResource("sessions.import.routineResolution.rememberAlias", defaultValue: "Remember header as routine alias", table: "Sessions"),
                        isOn: $viewModel.resolutionState.rememberRoutineAlias
                    )
                }

            case .none:
                Text(LocalizedStringResource("sessions.import.routineResolution.noneMessage", defaultValue: "Session will be imported without a routine.", table: "Sessions"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func exerciseResolutionSection(_ draft: NotesImportDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringResource("sessions.import.exerciseResolution.title", defaultValue: "Exercise Resolution", table: "Sessions"))
                .font(.headline)

            if viewModel.resolutionState.exerciseSelections.isEmpty {
                Text(LocalizedStringResource("sessions.import.exerciseResolution.empty", defaultValue: "No parsed exercises.", table: "Sessions"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(exerciseNames(from: draft), id: \.self) { rawName in
                if let selection = viewModel.resolutionState.exerciseSelections[rawName] {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: rawName)
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Picker(
                            LocalizedStringResource("sessions.import.exerciseResolution.mode", defaultValue: "Mode", table: "Sessions"),
                            selection: Binding(
                                get: { selection.mode },
                                set: { viewModel.resolutionState.exerciseSelections[rawName]?.mode = $0 }
                            )
                        ) {
                            ForEach(availableExerciseModes(for: rawName, selection: selection)) { mode in
                                Text(mode.titleResource).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        switch selection.mode {
                        case .matched:
                            Text(LocalizedStringResource("sessions.import.exerciseResolution.matched", defaultValue: "Matched: \(viewModel.selectedExercise(for: rawName)?.name ?? unknownText)", table: "Sessions"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if let matchedExercise = viewModel.selectedExercise(for: rawName) {
                                NavigationLink {
                                    SingleExerciseView(exercise: matchedExercise)
                                } label: {
                                    Text(LocalizedStringResource("sessions.import.exerciseResolution.viewDetails", defaultValue: "View Exercise Details", table: "Sessions"))
                                }
                                .font(.footnote)
                            }
                        case .existing:
                            Button {
                                exercisePickerRawName = rawName
                            } label: {
                                Text(LocalizedStringResource("sessions.import.exerciseResolution.chooseExercise", defaultValue: "Choose Exercise...", table: "Sessions"))
                            }
                            .buttonStyle(.bordered)

                            Text(LocalizedStringResource("sessions.import.exerciseResolution.selected", defaultValue: "Selected: \(viewModel.selectedExercise(for: rawName)?.name ?? noneText)", table: "Sessions"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if let selectedExercise = viewModel.selectedExercise(for: rawName) {
                                NavigationLink {
                                    SingleExerciseView(exercise: selectedExercise)
                                } label: {
                                    Text(LocalizedStringResource("sessions.import.exerciseResolution.viewDetails", defaultValue: "View Exercise Details", table: "Sessions"))
                                }
                                .font(.footnote)
                            }

                            Toggle(
                                LocalizedStringResource("sessions.import.exerciseResolution.rememberAlias", defaultValue: "Remember alias for this exercise", table: "Sessions"),
                                isOn: Binding(
                                    get: { viewModel.resolutionState.exerciseSelections[rawName]?.rememberAlias ?? false },
                                    set: { viewModel.resolutionState.exerciseSelections[rawName]?.rememberAlias = $0 }
                                )
                            )
                        case .createNew:
                            TextField(
                                text: Binding(
                                    get: { viewModel.resolutionState.exerciseSelections[rawName]?.newExerciseName ?? rawName },
                                    set: { viewModel.resolutionState.exerciseSelections[rawName]?.newExerciseName = $0 }
                                ),
                                prompt: Text(LocalizedStringResource("sessions.import.exerciseResolution.createName", defaultValue: "Create exercise name", table: "Sessions"))
                            ) {
                                Text(LocalizedStringResource("sessions.import.exerciseResolution.createNameLabel", defaultValue: "Create exercise name", table: "Sessions"))
                            }
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
            Text(LocalizedStringResource("sessions.import.parsed.title", defaultValue: "Parsed Items", table: "Sessions"))
                .font(.headline)

            ForEach(Array(draft.items.enumerated()), id: \.offset) { index, item in
                switch item {
                case .strength(let strength):
                    VStack(alignment: .leading, spacing: 6) {
                        Text(LocalizedStringResource("sessions.import.parsed.strengthHeading", defaultValue: "\(index + 1). Strength: \(strength.exerciseNameRaw)", table: "Sessions"))
                            .font(.footnote)
                            .fontWeight(.semibold)

                        ForEach(Array(strength.sets.enumerated()), id: \.offset) { setIndex, set in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(LocalizedStringResource("sessions.import.parsed.set", defaultValue: "Set \(setIndex + 1): \(setDescription(set))", table: "Sessions"))
                                    .font(.footnote)
                                if let details = perSideDescription(set) {
                                    Text(verbatim: details)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if let notes = strength.notes, !notes.isEmpty {
                            Text(LocalizedStringResource("sessions.import.parsed.note", defaultValue: "Note: \(notes)", table: "Sessions"))
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                case .cardio(let cardio):
                    VStack(alignment: .leading, spacing: 6) {
                        Text(LocalizedStringResource("sessions.import.parsed.cardioHeading", defaultValue: "\(index + 1). Cardio: \(cardio.exerciseNameRaw)", table: "Sessions"))
                            .font(.footnote)
                            .fontWeight(.semibold)

                        ForEach(Array(cardio.sets.enumerated()), id: \.offset) { setIndex, set in
                            Text(LocalizedStringResource("sessions.import.parsed.set", defaultValue: "Set \(setIndex + 1): \(cardioSetDescription(set))", table: "Sessions"))
                                .font(.footnote)
                        }

                        if let notes = cardio.notes, !notes.isEmpty {
                            Text(LocalizedStringResource("sessions.import.parsed.telemetry", defaultValue: "Telemetry: \(notes)", table: "Sessions"))
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
                Text(LocalizedStringResource("sessions.import.warnings.title", defaultValue: "Warnings", table: "Sessions"))
                    .font(.headline)

                ForEach(draft.warnings, id: \.self) { warning in
                    Text(verbatim: "• \(warning)")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            if !draft.unknownLines.isEmpty {
                Text(LocalizedStringResource("sessions.import.unknownLines.title", defaultValue: "Unknown Lines", table: "Sessions"))
                    .font(.headline)

                ForEach(Array(viewModel.unknownLinePreviewItems(for: draft).enumerated()), id: \.offset) { _, item in
                    Text(verbatim: "• \(item.line)")
                        .font(.footnote)
                        .foregroundStyle(unknownLineColor(item.classification))
                }
            }

            if let error = viewModel.resolutionState.errorMessage {
                Text(verbatim: error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let status = viewModel.resolutionState.statusMessage {
                Text(verbatim: status)
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 10) {
            Button {
                viewModel.resolveRoutine()
                viewModel.resolveExercise()
            } label: {
                Text(LocalizedStringResource("sessions.import.action.reResolve", defaultValue: "Re-Resolve", table: "Sessions"))
            }
            .buttonStyle(.bordered)

            Button {
                viewModel.batch = NotesImportBatch(drafts: [])
                viewModel.currentDraftIndex = 0
                viewModel.resolutionState = .empty
                draftDecisions = [:]
            } label: {
                Text(LocalizedStringResource("sessions.import.action.backToPaste", defaultValue: "Back to Paste", table: "Sessions"))
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
                Text(LocalizedStringResource("sessions.import.datetime.title", defaultValue: "Resolve Date & Time", table: "Sessions"))
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if needsDateResolution {
                    DatePicker(selection: $viewModel.selectedDateForCurrentDraft, displayedComponents: .date) {
                        Text(LocalizedStringResource("sessions.import.datetime.sessionDate", defaultValue: "Session Date", table: "Sessions"))
                    }
                    .datePickerStyle(.compact)

                    Button {
                        viewModel.applySelectedDateToCurrentDraft()
                    } label: {
                        Text(LocalizedStringResource("sessions.import.datetime.useDate", defaultValue: "Use This Date", table: "Sessions"))
                    }
                    .buttonStyle(.bordered)
                }

                DatePicker(
                    selection: Binding(
                        get: { viewModel.selectedStartForCurrentDraft },
                        set: { viewModel.setResolvedStart($0) }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                ) {
                    Text(LocalizedStringResource("sessions.import.datetime.start", defaultValue: "Start", table: "Sessions"))
                }
                .datePickerStyle(.compact)

                DatePicker(
                    selection: Binding(
                        get: { viewModel.selectedEndForCurrentDraft },
                        set: { viewModel.setResolvedEnd($0) }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                ) {
                    Text(LocalizedStringResource("sessions.import.datetime.end", defaultValue: "End", table: "Sessions"))
                }
                .datePickerStyle(.compact)

                if needsTimeResolution {
                    Button {
                        viewModel.useSuggestedTimeRangeForCurrentDraft()
                    } label: {
                        Text(LocalizedStringResource("sessions.import.datetime.useSuggestedTimeRange", defaultValue: "Use Suggested Time Range", table: "Sessions"))
                    }
                    .buttonStyle(.bordered)
                }

                if let validationMessage {
                    Text(verbatim: validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else {
            return String(localized: LocalizedStringResource("sessions.value.missing", defaultValue: "(missing)", table: "Sessions"))
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var noneText: String {
        String(localized: LocalizedStringResource("sessions.value.none", defaultValue: "None", table: "Sessions"))
    }

    private var unknownText: String {
        String(localized: LocalizedStringResource("sessions.value.unknown", defaultValue: "Unknown", table: "Sessions"))
    }

    private func pasteFromClipboardAdding() {
#if os(iOS)
        if let clipboardText = UIPasteboard.general.string {
            appendClipboardText(clipboardText)
        }
#elseif os(macOS)
        if let clipboardText = NSPasteboard.general.string(forType: .string) {
            appendClipboardText(clipboardText)
        }
#endif
    }

    private func pasteFromClipboardReplacing() {
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

    private func appendClipboardText(_ clipboardText: String) {
        let incoming = clipboardText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incoming.isEmpty else { return }

        let existing = viewModel.rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if existing.isEmpty {
            viewModel.rawInput = clipboardText
            return
        }

        viewModel.rawInput += "\n\n\(clipboardText)"
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
            weightText = String(localized: LocalizedStringResource("sessions.import.parsed.bodyweight", defaultValue: "bodyweight", table: "Sessions"))
        }

        var parts: [String] = [
            String(localized: LocalizedStringResource("sessions.import.parsed.strengthSetDetail", defaultValue: "\(set.reps)x @ \(weightText)", table: "Sessions"))
        ]
        if let restSeconds = set.restSeconds {
            parts.append(String(localized: LocalizedStringResource("sessions.import.parsed.restSeconds", defaultValue: "rest \(restSeconds)s", table: "Sessions")))
        }
        return parts.joined(separator: ", ")
    }

    private func perSideDescription(_ set: ParsedStrengthSet) -> String? {
        guard set.isPerSide else { return nil }
        guard let base = set.baseWeight, let perSide = set.perSideWeight else { return nil }
        let baseText = formattedNumber(base)
        let perSideText = formattedNumber(perSide)
        return String(localized: LocalizedStringResource("sessions.import.parsed.perSide", defaultValue: "Base \(baseText) + per-side \(perSideText)", table: "Sessions"))
    }

    private func cardioSetDescription(_ set: ParsedCardioSet) -> String {
        var parts: [String] = []
        if let duration = set.durationSeconds {
            parts.append(String(localized: LocalizedStringResource("sessions.import.parsed.durationSeconds", defaultValue: "duration \(duration)s", table: "Sessions")))
        }
        if let distance = set.distance {
            let distanceText = formattedNumber(distance)
            parts.append(String(localized: LocalizedStringResource("sessions.import.parsed.distance", defaultValue: "distance \(distanceText) \(set.distanceUnit.rawValue)", table: "Sessions")))
        }
        if let pace = set.paceSeconds {
            parts.append(String(localized: LocalizedStringResource("sessions.import.parsed.paceSeconds", defaultValue: "pace \(pace)s", table: "Sessions")))
        }
        if parts.isEmpty {
            return String(localized: LocalizedStringResource("sessions.import.parsed.noCardioMetrics", defaultValue: "no cardio metrics parsed", table: "Sessions"))
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

    private func unknownLineColor(_ classification: NotesImportViewModel.UnknownLineClassification) -> Color {
        switch classification {
        case .context:
            return .orange
        case .parseError:
            return .red
        case .neutral:
            return .secondary
        }
    }
}

private enum DraftDecision: Equatable {
    case confirmed
    case denied

    var titleResource: LocalizedStringResource {
        switch self {
        case .confirmed:
            return LocalizedStringResource("sessions.import.decision.confirmed", defaultValue: "Confirmed", table: "Sessions")
        case .denied:
            return LocalizedStringResource("sessions.import.decision.denied", defaultValue: "Denied", table: "Sessions")
        }
    }

    var titleText: String {
        String(localized: titleResource)
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

private extension NotesImportViewModel.RoutineResolutionMode {
    var titleResource: LocalizedStringResource {
        switch self {
        case .matched:
            return LocalizedStringResource("sessions.import.resolutionMode.matched", defaultValue: "Matched", table: "Sessions")
        case .existing:
            return LocalizedStringResource("sessions.import.resolutionMode.existing", defaultValue: "Existing", table: "Sessions")
        case .createNew:
            return LocalizedStringResource("sessions.import.resolutionMode.create", defaultValue: "Create", table: "Sessions")
        case .none:
            return LocalizedStringResource("sessions.value.none", defaultValue: "None", table: "Sessions")
        }
    }
}

private extension NotesImportViewModel.ExerciseResolutionMode {
    var titleResource: LocalizedStringResource {
        switch self {
        case .matched:
            return LocalizedStringResource("sessions.import.resolutionMode.matched", defaultValue: "Matched", table: "Sessions")
        case .existing:
            return LocalizedStringResource("sessions.import.resolutionMode.existing", defaultValue: "Existing", table: "Sessions")
        case .createNew:
            return LocalizedStringResource("sessions.import.resolutionMode.create", defaultValue: "Create", table: "Sessions")
        }
    }
}
