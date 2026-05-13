//
//  ExercisesView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftUI

// add new exercises
// add aliases to exercises
// assign split day to exercises

fileprivate struct ExerciseRowSnapshot: Identifiable {
    let id: UUID
    let name: String
    let isUserCreated: Bool
    let timestamp: Date
    let thumbnailURL: URL?
    let aliases: [String]
    let primaryMuscles: [String]
}

fileprivate struct ExerciseNavigationTarget: Hashable {
    let exerciseId: UUID
}

struct ExercisesView: View {
    @EnvironmentObject var exerciseService: ExerciseService
    @Environment(\.editMode) private var editMode
    @State private var searchText: String = ""
    @State private var selectedMuscle: String = ""
    @State private var showUserExercisesOnly: Bool = false
    @State private var exerciseRows: [ExerciseRowSnapshot] = []
    @State private var filteredRows: [ExerciseRowSnapshot] = []
    @State private var availableMuscles: [String] = []
    @EnvironmentObject var toastManager: ActionToastManager

    var body : some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    LocalizedStringResource(
                        "exercises.count",
                        defaultValue: "\(filteredRows.count) exercises",
                        table: "Exercises",
                        comment: "Count of exercises in the current list"
                    )
                )
                    .font(.caption)
                    .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)

                // Filter Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // All filter
                        FilterPill(
                            title: "All",
                            isSelected: selectedMuscle.isEmpty && !showUserExercisesOnly,
                            tableName: "Exercises"
                        )
                        .onTapGesture {
                            selectedMuscle = ""
                            showUserExercisesOnly = false
                        }

                        FilterPill(
                            title: "Mine",
                            isSelected: showUserExercisesOnly,
                            tableName: "Exercises"
                        )
                        .onTapGesture {
                            showUserExercisesOnly.toggle()
                            selectedMuscle = ""
                        }

                        // Muscle filters
                        ForEach(availableMuscles, id: \.self) { muscle in
                            muscleFilterPill(muscle)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 2)
                }
                .scrollClipDisabled()
                .padding(.vertical, 12)
            }
            .screenContentPadding()

            // Exercises List
            if exerciseRows.isEmpty {
                EmptyStateView(
                    title: "No Exercises",
                    systemImage: "dumbbell.fill",
                    message: "Create your first exercise.",
                    tableName: "Exercises"
                )
                .screenContentPadding()
            } else if filteredRows.isEmpty {
                EmptyStateView(
                    resourceTitle: emptyFilteredTitleResource,
                    systemImage: "magnifyingglass",
                    resourceMessage: emptyFilteredMessageResource
                )
                .screenContentPadding()
            } else {
                List {
                    ForEach(filteredRows) { row in
                        NavigationLink(value: ExerciseNavigationTarget(exerciseId: row.id)) {
                            ExerciseListRow(snapshot: row)
                        }
                        .cardListRowStyle()
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteExercise(id: row.id)
                            } label: {
                                Label {
                                    Text("Delete", tableName: "Exercises")
                                } icon: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                    }
                    .onDelete(perform: deleteFilteredExercises)
                }
                .cardListScreen()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: Text("Search exercises", tableName: "Exercises")
        )
        .appBackground()
        .navigationTitle(Text("Exercises", tableName: "Exercises"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ExerciseNavigationTarget.self) { target in
            SingleExerciseView(exerciseId: target.exerciseId)
        }
        .toolbar {
#if os(iOS)
            if !exerciseRows.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
#endif
            ToolbarItem {
                Button {
                    exerciseService.editingExercise = true
                } label: {
                    Label {
                        Text("Add Exercise", tableName: "Exercises")
                    } icon: {
                        Image(systemName: "plus.circle")
                    }
                }
            }
        }
        .onAppear {
            rebuildExerciseRows()
        }
        .onChange(of: exerciseService.exerciseListRevision) { _, _ in
            rebuildExerciseRows()
            if exerciseRows.isEmpty {
                editMode?.wrappedValue = .inactive
            }
        }
        .onChange(of: exerciseRows.isEmpty) {
            if exerciseRows.isEmpty {
                editMode?.wrappedValue = .inactive
            }
        }
        .onChange(of: searchText) { _, _ in
            refreshDerivedRows()
        }
        .onChange(of: selectedMuscle) { _, _ in
            refreshDerivedRows()
        }
        .onChange(of: showUserExercisesOnly) { _, _ in
            refreshDerivedRows()
        }
        .sheet(isPresented: $exerciseService.editingExercise) {
            NavigationView {
                VStack(spacing: 16) {
                    Text("Name your new exercise", tableName: "Exercises")
                        .font(.headline)

                    TextField(text: $exerciseService.editingContent, prompt: Text("Name", tableName: "Exercises")) {
                        Text("Name", tableName: "Exercises")
                    }
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                    Menu {
                        ForEach (ExerciseType.allCases, id: \.id) { exerciseType in
                            Button(exerciseType.name, action: { exerciseService.selectedExerciseType = exerciseType })
                        }
                   } label: {
                       Label {
                           Text(
                               LocalizedStringResource(
                                   "exercises.type.selected",
                                   defaultValue: "Exercise Type: \(exerciseService.selectedExerciseType.name)",
                                   table: "Exercises",
                                   comment: "Selected exercise type label"
                               )
                           )
                       } icon: {
                           Image(systemName: "chevron.down")
                       }
                   }

                    Button {
                        _ = exerciseService.addExercise()
                    } label: {
                        Label {
                            Text("Save", tableName: "Exercises")
                        } icon: {
                            Image(systemName: "plus.circle")
                        }
                            .font(.title2)
                            .padding()
                    }
                    .disabled(exerciseService.editingContent.trimmingCharacters(in: .whitespaces).isEmpty)

                    Spacer()
                }
                .padding()
                .navigationTitle(Text("Create New Exercise", tableName: "Exercises"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            exerciseService.editingExercise = false
                            exerciseService.editingContent = ""
                        } label: {
                            Text("Cancel", tableName: "Exercises")
                        }
                    }
                }
            }
        }
    }

    private func muscleFilterPill(_ muscle: String) -> some View {
        let isSelected = selectedMuscle == muscle
        return FilterPill(verbatimTitle: muscle, isSelected: isSelected)
            .onTapGesture {
                selectedMuscle = muscle
            }
    }

    private func deleteFilteredExercises(offsets: IndexSet) {
        let ids = offsets.compactMap { index in
            filteredRows.indices.contains(index) ? filteredRows[index].id : nil
        }
        deleteExercisesOptimistic(ids: ids)
    }

    private func deleteExercise(id: UUID) {
        deleteExercisesOptimistic(ids: [id])
    }

    private func deleteExercisesOptimistic(ids: [UUID]) {
        let toDelete = ids.compactMap { id in
            exerciseService.exercises.first(where: { $0.id == id })
        }
        guard !toDelete.isEmpty else { return }

        let archiveCount = toDelete.reduce(into: 0) { count, exercise in
            if exerciseService.willArchiveOnDelete(exercise) {
                count += 1
            }
        }

        exerciseService.removeExercises(toDelete)

        let isPlural = toDelete.count > 1
        let noun = isPlural ? "exercises" : "exercise"
        let message: String
        if archiveCount == toDelete.count {
            message = isPlural ? "Exercises have history. Will archive \(noun)." : "Exercise has history. Will archive \(noun)."
        } else if archiveCount == 0 {
            message = "Delete \(toDelete.count) \(noun)?"
        } else {
            message = "Will archive \(archiveCount), delete \(toDelete.count - archiveCount)."
        }

        let deletedItems = toDelete
        toastManager.add(
            message: message,
            intent: .undo,
            timeout: 4,
            onAction: {
                for exercise in deletedItems {
                    exerciseService.addRestoredExercise(exercise)
                }
            }
        )
    }

    private func rebuildExerciseRows() {
        exerciseRows = exerciseService.exercises.map { exercise in
            ExerciseRowSnapshot(
                id: exercise.id,
                name: exercise.name,
                isUserCreated: exercise.isUserCreated,
                timestamp: exercise.timestamp,
                thumbnailURL: exerciseService.thumbnailURL(for: exercise),
                aliases: exercise.aliases ?? [],
                primaryMuscles: exercise.primary_muscles ?? []
            )
        }
        refreshDerivedRows()
    }

    private func refreshDerivedRows() {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let scopedRows = showUserExercisesOnly
            ? exerciseRows.filter { $0.isUserCreated }
            : exerciseRows

        let searchMatchedRows = scopedRows.filter { row in
            matchesSearch(row, query: trimmedSearch)
        }

        availableMuscles = Array(
            Set(searchMatchedRows.flatMap(\.primaryMuscles))
        ).sorted()

        var resolvedSelectedMuscle = selectedMuscle
        if !resolvedSelectedMuscle.isEmpty,
           availableMuscles.contains(where: { $0.caseInsensitiveCompare(resolvedSelectedMuscle) == .orderedSame }) == false {
            resolvedSelectedMuscle = ""
            selectedMuscle = ""
        }

        filteredRows = searchMatchedRows.filter { row in
            guard !resolvedSelectedMuscle.isEmpty else { return true }
            return row.primaryMuscles.contains(where: {
                $0.caseInsensitiveCompare(resolvedSelectedMuscle) == .orderedSame
            })
        }
    }

    private func matchesSearch(_ row: ExerciseRowSnapshot, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        if row.name.localizedCaseInsensitiveContains(query) {
            return true
        }
        return row.aliases.contains { alias in
            alias.localizedCaseInsensitiveContains(query)
        }
    }

    private var emptyFilteredTitleResource: LocalizedStringResource {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if selectedMuscle.isEmpty {
                return LocalizedStringResource("exercises.empty.noResults", defaultValue: "No Results", table: "Exercises")
            }
            return LocalizedStringResource(
                "exercises.empty.noResultsInMuscle",
                defaultValue: "No Results in \(selectedMuscle)",
                table: "Exercises",
                comment: "Empty search title scoped to a muscle filter"
            )
        }

        if showUserExercisesOnly {
            return LocalizedStringResource("exercises.empty.noCustomExercises", defaultValue: "No Custom Exercises", table: "Exercises")
        }

        if !selectedMuscle.isEmpty {
            return LocalizedStringResource(
                "exercises.empty.noMuscleExercises",
                defaultValue: "No \(selectedMuscle) Exercises",
                table: "Exercises",
                comment: "Empty list title scoped to a muscle filter"
            )
        }

        return LocalizedStringResource("exercises.empty.noResults", defaultValue: "No Results", table: "Exercises")
    }

    private var emptyFilteredMessageResource: LocalizedStringResource {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty {
            return LocalizedStringResource(
                "exercises.empty.noSearchMatch",
                defaultValue: "No exercises match \"\(trimmedSearch)\".",
                table: "Exercises",
                comment: "Empty search message"
            )
        }

        if showUserExercisesOnly {
            return LocalizedStringResource("exercises.empty.createExercise", defaultValue: "Create an exercise to see it here.", table: "Exercises")
        }

        if !selectedMuscle.isEmpty {
            return LocalizedStringResource("exercises.empty.noMuscleMatch", defaultValue: "No exercises match this muscle filter.", table: "Exercises")
        }

        return LocalizedStringResource("exercises.empty.adjustFilters", defaultValue: "Try adjusting your filters.", table: "Exercises")
    }

}

private struct ExerciseListRow: View {
    let snapshot: ExerciseRowSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if snapshot.isUserCreated {
                VStack(alignment: .leading) {
                    Text(verbatim: snapshot.name)
                    HStack {
                        Text(snapshot.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                .padding(.vertical, 4)
            } else {
                HStack {
                    if let thumbnailURL = snapshot.thumbnailURL {
                        CachedThumbnailView(url: thumbnailURL)
                            .frame(width: 45, height: 45)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .clipped()
                            .padding(.trailing, 8)
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text(verbatim: snapshot.name)
                            Spacer()
                        }
                    }
                }
            }
        }
        .cardListRowContentPadding()
        .cornerRadius(12)
    }
}
