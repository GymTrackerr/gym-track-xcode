import SwiftUI
import SwiftData

struct NotesImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel = NotesImportViewModel()
    @State private var exercisePickerRawName: String?

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
                    onImportCompleted?()
                    dismiss()
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

            if draft.parsedDate == nil {
                DatePicker(
                    "Select Session Date",
                    selection: $viewModel.selectedDateForCurrentDraft,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)

                Button("Apply Selected Date") {
                    viewModel.applySelectedDateToCurrentDraft()
                }
                .buttonStyle(.bordered)
            }

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
                        case .existing:
                            Button("Choose Exercise…") {
                                exercisePickerRawName = rawName
                            }
                            .buttonStyle(.bordered)

                            Text("Selected: \(viewModel.selectedExercise(for: rawName)?.name ?? "None")")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

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
                    Text("\(index + 1). Strength: \(strength.exerciseNameRaw) (\(strength.sets.count) sets)")
                        .font(.footnote)
                case .cardio(let cardio):
                    Text("\(index + 1). Cardio: \(cardio.exerciseNameRaw) (\(cardio.sets.count) sets)")
                        .font(.footnote)
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
            HStack(spacing: 10) {
                Button("Re-Resolve") {
                    viewModel.resolveRoutine()
                    viewModel.resolveExercise()
                }
                .buttonStyle(.bordered)

                Button {
                    if viewModel.confirmImport() {
                        onImportCompleted?()
                        dismiss()
                    }
                } label: {
                    if viewModel.isCommitting {
                        ProgressView()
                    } else {
                        Text("Confirm Import")
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            Button("Back to Paste") {
                viewModel.batch = NotesImportBatch(drafts: [])
                viewModel.currentDraftIndex = 0
                viewModel.resolutionState = .empty
            }
            .buttonStyle(.bordered)
        }
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "(missing)" }
        return date.formatted(date: .abbreviated, time: .shortened)
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
}
