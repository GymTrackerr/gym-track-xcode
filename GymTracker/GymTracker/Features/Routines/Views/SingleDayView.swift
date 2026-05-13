//
//  SingleDayView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftUI

// TODO: manage feature with more than one exercise of the same type
// adding exercise UI needs to be updated to support
// backend needs to delete by ID, look at sessionExercises
// show "last completed split(/exercise)" in view - same in exercises
// and a "last edited"

struct SingleDayView: View {
    @EnvironmentObject var esdService: ExerciseSplitDayService
    @EnvironmentObject var exerciseService: ExerciseService
    @EnvironmentObject var splitDayService: RoutineService
    @EnvironmentObject var progressionService: ProgressionService
    @Bindable var routine: Routine
    
    @State private var routineAliasDraft: String = ""
    @State private var showingProgressionSheet = false
    @EnvironmentObject var toastManager: ActionToastManager
    @Environment(\.editMode) private var editMode

    private var defaultProgressionName: String {
        if let profile = progressionService.profile(id: routine.defaultProgressionProfileId) {
            return profile.isBuiltIn ? profile.type.title : profile.name
        }
        return routine.defaultProgressionProfileNameSnapshot ??
        String(localized: LocalizedStringResource("progression.value.none", defaultValue: "None", table: "Progression"))
    }

    private var exerciseCountText: String {
        String(localized: LocalizedStringResource(
            "routines.exercise.count",
            defaultValue: "\(routine.exerciseSplits.count) exercises",
            table: "Routines"
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            if (editMode?.wrappedValue == .inactive){
                CardRowContainer {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: routine.name)
                                .font(.title3.weight(.semibold))
                            Text(verbatim: exerciseCountText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        VStack(spacing: 6) {
                            detailRow(
                                titleResource: LocalizedStringResource("routines.detail.order", defaultValue: "Order", table: "Routines"),
                                value: "\(routine.order)"
                            )
                            detailRow(
                                titleResource: LocalizedStringResource("routines.detail.date", defaultValue: "Date", table: "Routines"),
                                value: routine.timestamp.formatted(date: .abbreviated, time: .omitted)
                            )
                            detailRow(
                                titleResource: LocalizedStringResource(
                                    "progression.title",
                                    defaultValue: "Progression",
                                    table: "Progression"
                                ),
                                value: defaultProgressionName
                            )
                        }

                        if !routine.aliases.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(routine.aliases, id: \.self) { alias in
                                        Text(verbatim: alias)
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .controlCapsuleSurface()
                                    }
                                }
                            }
                        }
                    }
                }
                .screenContentPadding()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(LocalizedStringResource("routines.section.identity", defaultValue: "Identity", table: "Routines"))
                        .font(.headline)

                    TextField(
                        text: $routine.name,
                        prompt: Text(LocalizedStringResource("routines.field.routineName", defaultValue: "Routine Name", table: "Routines"))
                    ) {
                        Text(LocalizedStringResource("routines.field.routineName", defaultValue: "Routine Name", table: "Routines"))
                    }
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 8) {
                        TextField(
                            text: $routineAliasDraft,
                            prompt: Text(LocalizedStringResource("routines.field.addAlias", defaultValue: "Add alias", table: "Routines"))
                        ) {
                            Text(LocalizedStringResource("routines.field.addAlias", defaultValue: "Add alias", table: "Routines"))
                        }
                            .textFieldStyle(.roundedBorder)

                        Button {
                            addRoutineAlias()
                        } label: {
                            Text(LocalizedStringResource("routines.action.add", defaultValue: "Add", table: "Routines"))
                        }
                        .buttonStyle(.bordered)
                        .disabled(routineAliasDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if !routine.aliases.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(routine.aliases, id: \.self) { alias in
                                    HStack(spacing: 4) {
                                        Text(verbatim: alias)
                                            .font(.caption)
                                        Button {
                                            removeRoutineAlias(alias)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .controlCapsuleSurface()
                                }
                            }
                        }
                    }

                    Button {
                        showingProgressionSheet = true
                    } label: {
                        HStack {
                            Text(
                                LocalizedStringResource(
                                    "progression.routine.defaultProgression",
                                    defaultValue: "Default Progression",
                                    table: "Progression"
                                )
                            )
                            Spacer()
                            Text(verbatim: defaultProgressionName)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .screenContentPadding()
            }
            
            List {
                Section {
                    ForEach(routine.exerciseSplits.sorted { $0.order < $1.order }, id: \.id) { exerciseSplit in
                        NavigationLink {
                            SingleExerciseView(exercise: exerciseSplit.exercise)
                                .appBackground()
                        } label: {
                            SingleExerciseLabelView(exercise: exerciseSplit.exercise, orderInSplit: exerciseSplit.order)
                                .foregroundColor(.primary)
                                .cardListRowContentPadding()
                        }
                        .cardListRowStyle()
                    }
                    .onDelete(perform: removeExercise)
                    .onMove(perform: moveExercise)
                } header: {
                    Text(LocalizedStringResource("routines.section.exercises", defaultValue: "Exercises", table: "Routines"))
                }

                Section {
                    ForEach(routine.sessions.sorted { $0.timestampDone > $1.timestampDone }, id: \.id) { session in
                        NavigationLink {
                            SingleSessionView(session: session)
                                .appBackground()
                        } label: {
                            SingleSessionLabelView(session: session)
                                .foregroundColor(.primary)
                        }
                        .cardListRowStyle()
                    }
                } header: {
                    Text(LocalizedStringResource("routines.section.sessionHistory", defaultValue: "Session History", table: "Routines"))
                }
            }
            .cardListScreen()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .appBackground()
        .navigationTitle(routine.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationLink {
                    RoutineHistoryChartView(routine: routine)
                        .appBackground()
                } label: {
                    Label {
                        Text(LocalizedStringResource("routines.action.charts", defaultValue: "Charts", table: "Routines"))
                    } icon: {
                        Image(systemName: "chart.bar.xaxis")
                    }
                }
            }
            
        #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
        #endif
            ToolbarItem {
                Button {
                    exerciseService.editingContent = ""
                    esdService.addingExerciseSplit = true
                } label: {
                    Label {
                        Text(LocalizedStringResource("routines.action.addExercise", defaultValue: "Add Exercise", table: "Routines"))
                    } icon: {
                        Image(systemName: "plus.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $esdService.addingExerciseSplit) {
            RoutineExercisePickerSheet(
                titleResource: LocalizedStringResource("exercises.picker.addExercises", defaultValue: "Add Exercises", table: "Exercises"),
                searchText: $exerciseService.editingContent,
                exercises: exerciseService.exercises,
                isSyncingCatalog: false,
                syncStatusText: "",
                progressCompleted: 0,
                progressTotal: 0,
                onCreate: {
                    let exerciseNew = exerciseService.addExercise()
                    DispatchQueue.main.async {
                        if let exercise = exerciseNew {
                            addExerciseEditing(exercise: exercise)
                        }
                    }
                },
                canCreate: !exerciseService.editingContent.trimmingCharacters(in: .whitespaces).isEmpty,
                showsMinusIcon: { exercise in
                    esdService.showingMinusIcon(routine: routine, id: exercise.id)
                },
                onToggle: { exercise in
                    if esdService.showingMinusIcon(routine: routine, id: exercise.id) {
                        removeExerciseEditing(exercise: exercise)
                    } else {
                        addExerciseEditing(exercise: exercise)
                    }
                },
                onSave: {
                    esdService.confirmEditing(routine: routine)
                    exerciseService.editingContent = ""
                },
                onCancel: {
                    esdService.endEditing()
                    exerciseService.editingContent = ""
                    exerciseService.editingContent = ""
                }
            )
        }
        .sheet(isPresented: $showingProgressionSheet) {
            NavigationStack {
                RoutineProgressionSheet(routine: routine)
            }
        }
    }

    func removeExerciseEditing(exercise: Exercise) {
        if (esdService.isInAdding(id: exercise.id)) {
            esdService.addingExercises.removeAll { $0.id == exercise.id }
            
        } else {
            esdService.removingExercises.append(exercise)
        }
    }
    
    func addExerciseEditing(exercise: Exercise) {
        if (esdService.isInRemoving(id: exercise.id)) {
            esdService.removingExercises.removeAll { $0.id == exercise.id }
        } else {
            esdService.addingExercises.append(exercise)
        }
    }
    func removeExercise(offsets: IndexSet) {
        let sortedSplits = routine.exerciseSplits.sorted { $0.order < $1.order }
        let splitIds = offsets.compactMap { index in
            sortedSplits.indices.contains(index) ? sortedSplits[index].id : nil
        }
        removeExerciseOptimistic(splitIds: splitIds)
    }
    
    func moveExercise(from source: IndexSet, to destination: Int) {
        withTransaction(Transaction(animation: .default)) {
            esdService.moveExercise(routine: routine, from: source, to: destination)
        }

//        esdService.moveExercise(routine: routine, from: source, to: destination)
    }

    private func addRoutineAlias() {
        let trimmed = routineAliasDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var aliases = routine.aliases
        if aliases.contains(where: { $0.compare(trimmed, options: .caseInsensitive) == .orderedSame }) {
            routineAliasDraft = ""
            return
        }

        aliases.append(trimmed)
        _ = splitDayService.setAliases(for: routine, aliases: aliases)
        routineAliasDraft = ""
    }

    private func removeRoutineAlias(_ alias: String) {
        let updated = routine.aliases.filter { $0 != alias }
        _ = splitDayService.setAliases(for: routine, aliases: updated)
    }

    @ViewBuilder
    private func detailRow(titleResource: LocalizedStringResource, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(titleResource)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: value)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
    }

    private func removeExerciseOptimistic(splitIds: [UUID]) {
        let toRemove = routine.exerciseSplits.filter { split in
            splitIds.contains(split.id)
        }
        guard !toRemove.isEmpty else { return }

        esdService.removeExercise(routine: routine, splitIds: splitIds)

        let count = toRemove.count
        let removedItems = toRemove
        toastManager.add(
            message: String(localized: LocalizedStringResource(
                "routines.toast.removeExercises",
                defaultValue: "Remove \(count) exercises from routine?",
                table: "Routines"
            )),
            intent: .undo,
            timeout: 4,
            onAction: {
                for split in removedItems {
                    esdService.addRestoredExerciseSplit(routine: routine, exerciseSplit: split)
                }
            }
        )
    }
}

private struct RoutineProgressionSheet: View {
    @EnvironmentObject private var progressionService: ProgressionService
    @EnvironmentObject private var esdService: ExerciseSplitDayService
    @Environment(\.dismiss) private var dismiss

    let routine: Routine

    @State private var selectedProfileId: UUID?

    var body: some View {
        Form {
            Section {
                Picker(
                    LocalizedStringResource(
                        "progression.detail.profile",
                        defaultValue: "Profile",
                        table: "Progression"
                    ),
                    selection: $selectedProfileId
                ) {
                    Text(LocalizedStringResource("progression.value.none", defaultValue: "None", table: "Progression"))
                        .tag(Optional<UUID>.none)
                    ForEach(progressionService.profiles, id: \.id) { profile in
                        profileNameText(profile).tag(Optional(profile.id))
                    }
                }

                Text(
                    LocalizedStringResource(
                        "progression.routine.description",
                        defaultValue: "Routine sessions will automatically apply this profile to exercises that do not already have their own saved progression.",
                        table: "Progression"
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(LocalizedStringResource("progression.routine.defaultProgression", defaultValue: "Default Progression", table: "Progression"))
            }
        }
        .screenContentPadding()
        .navigationTitle(Text(LocalizedStringResource("progression.routine.title", defaultValue: "Routine Progression", table: "Progression")))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Text(LocalizedStringResource("progression.action.cancel", defaultValue: "Cancel", table: "Progression"))
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    let selectedProfile = progressionService.profile(id: selectedProfileId)
                    routine.defaultProgressionProfileId = selectedProfile?.id
                    routine.defaultProgressionProfileNameSnapshot = selectedProfile?.name
                    esdService.saveChanges()
                    dismiss()
                } label: {
                    Text(LocalizedStringResource("progression.action.save", defaultValue: "Save", table: "Progression"))
                }
            }
        }
        .onAppear {
            progressionService.ensureBuiltInProfiles()
            progressionService.loadProfiles()
            selectedProfileId = routine.defaultProgressionProfileId
        }
    }

    private func profileNameText(_ profile: ProgressionProfile) -> Text {
        if profile.isBuiltIn {
            return Text(profile.type.titleResource)
        }
        return Text(verbatim: profile.name)
    }
}

struct SingleDayLabelView: View {
    @Bindable var routine: Routine
    
    var body : some View {
        ZStack {
            VStack(alignment: .leading) {
                Text(verbatim: routine.name)
                HStack {
                    Text(LocalizedStringResource(
                        "routines.label.dayNumber",
                        defaultValue: "Day #\(routine.order + 1)",
                        table: "Routines"
                    ))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()
                    Text(routine.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
