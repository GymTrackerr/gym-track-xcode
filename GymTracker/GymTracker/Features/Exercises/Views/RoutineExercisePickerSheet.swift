import SwiftUI

struct RoutineExercisePickerSheet: View {
    let title: String
    @Binding var searchText: String
    let searchResults: [Exercise]
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
    let onSearchChange: () -> Void

    private var progressValue: Double? {
        guard progressTotal > 0 else { return nil }
        return Double(progressCompleted) / Double(progressTotal)
    }

    private var resolvedStatusText: String {
        let trimmed = syncStatusText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return isSyncingCatalog ? "Syncing ExerciseDB..." : "ExerciseDB is ready."
        }
        return trimmed
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                if isSyncingCatalog || !syncStatusText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            if isSyncingCatalog {
                                ProgressView()
                                    .controlSize(.small)
                            }

                            Text(resolvedStatusText)
                                .font(.subheadline.weight(.semibold))

                            Spacer()
                        }

                        if let progressValue {
                            ProgressView(value: progressValue)
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
                    ForEach(searchResults, id: \.id) { exercise in
                        Button {
                            onToggle(exercise)
                        } label: {
                            HStack {
                                Image(systemName: showsMinusIcon(exercise) ? "minus" : "plus")
                                Text(exercise.name)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)

                Spacer()
            }
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
            .onChange(of: searchText) {
                onSearchChange()
            }
        }
    }
}
