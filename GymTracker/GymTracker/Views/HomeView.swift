import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var splitDays: [SplitDay]
    
    @State private var editingSplit: Bool = false
    @State private var editingContent: String = ""
    
    var body: some View {
        List {
            ForEach(splitDays) { splitDay in
                NavigationLink {
                    VStack(alignment: .leading) {
                        Text("SplitDay: \(splitDay.name)")
                        Text("Order: \(splitDay.order)")
                        Text("Date: \(splitDay.timestamp.formatted(date: .numeric, time: .omitted))")
                    }
                    .padding()
                } label: {
                    VStack(alignment: .leading) {
                        Text(splitDay.name)
                        Text(splitDay.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .onDelete(perform: removeSplitDay)
        }
        .navigationTitle("Home")
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
#endif
            ToolbarItem {
                Button {
                    editingSplit = true
                } label: {
                    Label("Add Split Day", systemImage: "plus.circle")
                }
            }
        }
        .sheet(isPresented: $editingSplit) {
            NavigationView {
                VStack(spacing: 16) {
                    Text("Name your new split day")
                        .font(.headline)
                    
                    TextField("Name", text: $editingContent)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                    
                    Button {
                        addSplitDay(name: editingContent)
                    } label: {
                        Label("Save", systemImage: "plus.circle")
                            .font(.title2)
                            .padding()
                    }
                    .disabled(editingContent.trimmingCharacters(in: .whitespaces).isEmpty)
                    
                    Spacer()
                }
                .padding()
                .navigationTitle("Create New Split Day")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            editingSplit = false
                            editingContent = ""
                        }
                    }
                }
            }
        }
    }
    
    private func addSplitDay(name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        
        withAnimation {
            let newItem = SplitDay(order: splitDays.count, name: trimmedName)
            modelContext.insert(newItem)
            do {
                try modelContext.save()
                // Clear and dismiss sheet after successful save
                editingSplit = false
                editingContent = ""
            } catch {
                print("Failed to save new split day: \(error)")
            }
        }
    }
    
    private func removeSplitDay(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(splitDays[index])
            }
            do {
                try modelContext.save()
            } catch {
                print("Failed to save after deletion: \(error)")
            }
        }
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .modelContainer(for: SplitDay.self, inMemory: true)
    }
}
