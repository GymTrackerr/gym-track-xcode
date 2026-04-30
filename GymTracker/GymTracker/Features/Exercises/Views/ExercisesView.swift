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
            // Header
            VStack(alignment: .leading, spacing: 8) {
//                Text("Exercises")
//                    .font(.title2)
//                    .fontWeight(.bold)
                
                Text("\(filteredRows.count) exercises")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            // Filter Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // All filter
                    FilterPill(
                        title: "All",
                        isSelected: selectedMuscle.isEmpty && !showUserExercisesOnly
                    )
                    .onTapGesture {
                        selectedMuscle = ""
                        showUserExercisesOnly = false
                    }

                    FilterPill(
                        title: "Mine",
                        isSelected: showUserExercisesOnly
                    )
                    .onTapGesture {
                        showUserExercisesOnly.toggle()
                        selectedMuscle = ""
                    }

                    // Muscle filters
                    ForEach(availableMuscles, id: \.self) { muscle in
                        FilterPill(
                            title: muscle,
                            isSelected: selectedMuscle == muscle
                        )
                        .onTapGesture {
                            selectedMuscle = muscle
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 12)

            // Exercises List
            if exerciseRows.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("No Exercises")
                        .font(.headline)
                    
                    Text("Create your first exercise")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
                .padding()
            } else if filteredRows.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("No Results\(selectedMuscle != "" ? " in \(selectedMuscle)" : "")")
                        .font(.headline)
                    
                    Text("No exercises match \"\(searchText)\"")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(filteredRows) { row in
                        NavigationLink(value: ExerciseNavigationTarget(exerciseId: row.id)) {
                            ExerciseListRow(snapshot: row)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                                .padding(.vertical, 4)
                                .padding(.horizontal, 4)
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteExercise(id: row.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete(perform: deleteFilteredExercises)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search exercises"
        )
        .appBackground()
        .navigationTitle("Exercises")
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
                    Label("Add Exercise", systemImage: "plus.circle")
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
                    Text("Name your new exercise")
                        .font(.headline)

                    TextField("Name", text: $exerciseService.editingContent)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                    Menu {
                        ForEach (ExerciseType.allCases, id: \.id) { exerciseType in
                            Button(exerciseType.name, action: { exerciseService.selectedExerciseType = exerciseType })
                        }
                   } label: {
                       Label("Exercise Type: \(exerciseService.selectedExerciseType.name)", systemImage: "chevron.down")
                   }

                    Button {
                        _ = exerciseService.addExercise()
                    } label: {
                        Label("Save", systemImage: "plus.circle")
                            .font(.title2)
                            .padding()
                    }
                    .disabled(exerciseService.editingContent.trimmingCharacters(in: .whitespaces).isEmpty)

                    Spacer()
                }
                .padding()
                .navigationTitle("Create New Exercise")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            exerciseService.editingExercise = false
                            exerciseService.editingContent = ""
                        }
                    }
                }
            }
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

}

private struct ExerciseListRow: View {
    let snapshot: ExerciseRowSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if snapshot.isUserCreated {
                VStack(alignment: .leading) {
                    Text(snapshot.name)
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
                            Text(snapshot.name)
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding(8)
        .cornerRadius(12)
    }
}
//
//// Filter Pill Component
//struct FilterPill: View {
//    let title: String
//    let isSelected: Bool
//
//    var body: some View {
//        Text(title)
//            .font(.caption)
//            .fontWeight(.semibold)
//            .padding(.horizontal, 16)
//            .padding(.vertical, 8)
//            .background(isSelected ? Color.accentColor : Color.gray.opacity(0.2))
//            .foregroundColor(isSelected ? .white : .primary)
//            .cornerRadius(20)
//    }
//}
//
