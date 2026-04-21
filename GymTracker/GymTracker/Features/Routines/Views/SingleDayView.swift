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
    
    @State var searchResults: [Exercise] = []
    @State private var routineAliasDraft: String = ""
    @State private var showingProgressionSheet = false
    @EnvironmentObject var toastManager: ActionToastManager
    @Environment(\.editMode) private var editMode

    private var defaultProgressionName: String {
        progressionService.profile(id: routine.defaultProgressionProfileId)?.name ??
        routine.defaultProgressionProfileNameSnapshot ??
        "None"
    }

    var body: some View {
        VStack {
            if (editMode?.wrappedValue == .inactive){
                VStack(alignment: .leading) {
                    Text("Routine: \(routine.name)")
                    Text("Order: \(routine.order)")
                    Text("Date: \(routine.timestamp.formatted(date: .numeric, time: .omitted))")
                    Text("Progression: \(defaultProgressionName)")

                    if !routine.aliases.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(routine.aliases, id: \.self) { alias in
                                    Text(alias)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color(.systemGray5))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
                .padding()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Identity")
                        .font(.headline)
                        .padding(.horizontal)

                    TextField("Routine Name", text: $routine.name)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)

                    HStack(spacing: 8) {
                        TextField("Add alias", text: $routineAliasDraft)
                            .textFieldStyle(.roundedBorder)

                        Button("Add") {
                            addRoutineAlias()
                        }
                        .buttonStyle(.bordered)
                        .disabled(routineAliasDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal)

                    if !routine.aliases.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(routine.aliases, id: \.self) { alias in
                                    HStack(spacing: 4) {
                                        Text(alias)
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
                                    .background(Color(.systemGray5))
                                    .clipShape(Capsule())
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    Button {
                        showingProgressionSheet = true
                    } label: {
                        HStack {
                            Text("Default Progression")
                            Spacer()
                            Text(defaultProgressionName)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }
            }
            
            List {
                Section {
                    ForEach(routine.exerciseSplits.sorted { $0.order < $1.order }, id: \.id) { exerciseSplit in
                        NavigationLink {
                            SingleExerciseView(exercise: exerciseSplit.exercise)
                        } label: {
                            SingleExerciseLabelView(exercise: exerciseSplit.exercise, orderInSplit: exerciseSplit.order)
                                .foregroundColor(.primary)
                        }
                        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                                .padding(.vertical, 6)
                                .padding(.horizontal, 4)
                        )
                    }
                    .onDelete(perform: removeExercise)
                    .onMove(perform: moveExercise)
                } header: {
                    Text("Exercises")
                }

                Section {
                    ForEach(routine.sessions.sorted { $0.timestampDone > $1.timestampDone }, id: \.id) { session in
                        NavigationLink {
                            SingleSessionView(session: session)
                        } label: {
                            SingleSessionLabelView(session: session)
                                .foregroundColor(.primary)
                        }
                        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                                .padding(.vertical, 6)
                                .padding(.horizontal, 4)
                        )
                    }
                } header: {
                    Text("Session History")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(routine.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationLink {
                    RoutineHistoryChartView(routine: routine)
                        .appBackground()
                } label: {
                    Label("Charts", systemImage: "chart.bar.xaxis")
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
                    performSearch()
                    esdService.addingExerciseSplit = true
                } label: {
                    Label("Add Exercise", systemImage: "plus.circle")
                }
            }
        }
        .sheet(isPresented: $esdService.addingExerciseSplit) {
            RoutineExercisePickerSheet(
                title: "Add Exercises",
                searchText: $exerciseService.editingContent,
                searchResults: searchResults,
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
                },
                onSearchChange: performSearch
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
    func performSearch() {
        print("searching \(exerciseService.editingContent)")
        searchResults = exerciseService.search(query: exerciseService.editingContent)
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

    private func removeExerciseOptimistic(splitIds: [UUID]) {
        let toRemove = routine.exerciseSplits.filter { split in
            splitIds.contains(split.id)
        }
        guard !toRemove.isEmpty else { return }

        esdService.removeExercise(routine: routine, splitIds: splitIds)

        let count = toRemove.count
        let noun = count == 1 ? "exercise" : "exercises"
        let removedItems = toRemove
        toastManager.add(
            message: "Remove \(count) \(noun) from routine?",
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
            Section("Default Progression") {
                Picker("Profile", selection: $selectedProfileId) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(progressionService.profiles, id: \.id) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }

                Text("Routine sessions will automatically apply this profile to exercises that do not already have their own saved progression.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Routine Progression")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let selectedProfile = progressionService.profile(id: selectedProfileId)
                    routine.defaultProgressionProfileId = selectedProfile?.id
                    routine.defaultProgressionProfileNameSnapshot = selectedProfile?.name
                    esdService.saveChanges()
                    dismiss()
                }
            }
        }
        .onAppear {
            progressionService.ensureBuiltInProfiles()
            progressionService.loadProfiles()
            selectedProfileId = routine.defaultProgressionProfileId
        }
    }
}

struct SingleDayLabelView: View {
    @Bindable var routine: Routine
    
    var body : some View {
        ZStack {
            VStack(alignment: .leading) {
                Text(routine.name)
                HStack {
                    Text("Day #\(routine.order+1)")
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
