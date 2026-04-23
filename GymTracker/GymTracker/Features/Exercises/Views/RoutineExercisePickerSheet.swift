import SwiftUI

struct RoutineExercisePickerSheet: View {
    let title: String
    @Binding var searchText: String
    let exercises: [Exercise]
    let isSyncingCatalog: Bool
    let syncStatusText: String
    let progressCompleted: Int
    let progressTotal: Int
    let onCreate: () -> Void
    let canCreate: Bool
    let showsMinusIcon: (Exercise) -> Bool
    let onToggle: (Exercise) -> Void
    let onSave: () -> Void
    let onCancel: () -> Void

    private var filteredExercises: [Exercise] {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return exercises }

        return exercises.filter { exercise in
            if exercise.name.localizedCaseInsensitiveContains(trimmedQuery) {
                return true
            }

            if (exercise.aliases ?? []).contains(where: { $0.localizedCaseInsensitiveContains(trimmedQuery) }) {
                return true
            }

            if (exercise.primary_muscles ?? []).contains(where: { $0.localizedCaseInsensitiveContains(trimmedQuery) }) {
                return true
            }

            return (exercise.secondary_muscles ?? []).contains(where: { $0.localizedCaseInsensitiveContains(trimmedQuery) })
        }
    }

    var body: some View {
        ZStack {
            NavigationView {
                VStack(spacing: 16) {
                    if isSyncingCatalog {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)

                                Text(syncStatusText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Syncing ExerciseDB..." : syncStatusText)
                                    .font(.subheadline.weight(.semibold))

                                Spacer()
                            }

                            if progressTotal > 0 {
                                ProgressView(value: Double(progressCompleted) / Double(progressTotal))
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    TextField("Search or Create Exercise", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        onCreate()
                    } label: {
                        Label("Add", systemImage: "plus.circle")
                            .font(.title2)
                            .padding(.vertical, 4)
                    }
                    .disabled(!canCreate)

                    List {
                        ForEach(filteredExercises, id: \.id) { exercise in
                            Button {
                                onToggle(exercise)
                            } label: {
                                HStack {
                                    Image(systemName: showsMinusIcon(exercise) ? "minus" : "plus")
                                    Text(exercise.name)
                                }
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding()
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save", action: onSave)
                    }

                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                    }
                }
            }
        }
        .appBackground()
    }
}
