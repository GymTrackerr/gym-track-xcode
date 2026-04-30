import SwiftUI

struct NotesImportExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var viewModel: NotesImportViewModel
    let rawName: String

    @State private var searchText: String = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Original Exercise") {
                    Text(rawName)
                        .font(.headline)
                }

                Section("Existing Exercises") {
                    ForEach(filteredExercises, id: \.id) { exercise in
                        Button {
                            viewModel.chooseExistingExercise(rawName: rawName, exercise: exercise)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise.name)
                                    .foregroundStyle(.primary)

                                if let aliases = exercise.aliases, !aliases.isEmpty {
                                    Text(aliases.joined(separator: ", "))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
            .screenContentPadding()
            .navigationTitle("Choose Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search name or alias")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var filteredExercises: [Exercise] {
        viewModel.filteredUserExercises(searchText: searchText)
    }
}
