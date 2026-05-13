import SwiftUI

struct RoutineExercisePickerSheet: View {
    let titleResource: LocalizedStringResource
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

                                if syncStatusText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(LocalizedStringResource("exercises.picker.syncingExerciseDB", defaultValue: "Syncing ExerciseDB...", table: "Exercises"))
                                        .font(.subheadline.weight(.semibold))
                                } else {
                                    Text(verbatim: syncStatusText)
                                        .font(.subheadline.weight(.semibold))
                                }

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

                    TextField(
                        text: $searchText,
                        prompt: Text(LocalizedStringResource("exercises.picker.searchOrCreate", defaultValue: "Search or Create Exercise", table: "Exercises"))
                    ) {
                        Text(LocalizedStringResource("exercises.picker.searchOrCreate", defaultValue: "Search or Create Exercise", table: "Exercises"))
                    }
                        .textFieldStyle(.roundedBorder)

                    Button {
                        onCreate()
                    } label: {
                        Label {
                            Text(LocalizedStringResource("exercises.action.add", defaultValue: "Add", table: "Exercises"))
                        } icon: {
                            Image(systemName: "plus.circle")
                        }
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
                                    Text(verbatim: exercise.name)
                                }
                                .cardListRowContentPadding()
                            }
                            .buttonStyle(.plain)
                            .cardListRowStyle()
                        }
                    }
                    .cardListScreen()

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .screenContentPadding()
                .navigationTitle(Text(titleResource))
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: onSave) {
                            Text(LocalizedStringResource("shared.action.save", defaultValue: "Save", table: "Shared"))
                        }
                    }

                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: onCancel) {
                            Text(LocalizedStringResource("shared.action.cancel", defaultValue: "Cancel", table: "Shared"))
                        }
                    }
                }
            }
        }
        .appBackground()
    }
}
