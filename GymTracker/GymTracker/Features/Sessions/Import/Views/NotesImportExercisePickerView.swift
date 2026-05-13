import SwiftUI

struct NotesImportExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var viewModel: NotesImportViewModel
    let rawName: String

    @State private var searchText: String = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(verbatim: rawName)
                        .font(.headline)
                } header: {
                    Text(LocalizedStringResource("sessions.import.exercisePicker.originalSection", defaultValue: "Original Exercise", table: "Sessions"))
                }

                Section {
                    ForEach(filteredExercises, id: \.id) { exercise in
                        Button {
                            viewModel.chooseExistingExercise(rawName: rawName, exercise: exercise)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: exercise.name)
                                    .foregroundStyle(.primary)

                                if let aliases = exercise.aliases, !aliases.isEmpty {
                                    Text(verbatim: aliases.joined(separator: ", "))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                } header: {
                    Text(LocalizedStringResource("sessions.import.exercisePicker.existingSection", defaultValue: "Existing Exercises", table: "Sessions"))
                }
            }
            .screenContentPadding()
            .navigationTitle(Text(LocalizedStringResource("sessions.import.exercisePicker.title", defaultValue: "Choose Exercise", table: "Sessions")))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: Text(LocalizedStringResource("sessions.import.exercisePicker.search.placeholder", defaultValue: "Search name or alias", table: "Sessions")))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text(LocalizedStringResource("sessions.action.close", defaultValue: "Close", table: "Sessions"))
                    }
                }
            }
        }
    }

    private var filteredExercises: [Exercise] {
        viewModel.filteredUserExercises(searchText: searchText)
    }
}
