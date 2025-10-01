import SwiftUI
import SwiftData

struct HomeView: View {
//    @EnvironmentObject var manager: TrackerManager
    
    var body: some View {
        SplitDaysView()
    }
    
//    private func addSplitDay(name: String) {
//        let trimmedName = name.trimmingCharacters(in: .whitespaces)
//        guard !trimmedName.isEmpty else { return }
//        
//        withAnimation {
//            let newItem = SplitDay(order: splitDays.count, name: trimmedName)
//            modelContext.insert(newItem)
//            do {
//                try modelContext.save()
//                // Clear and dismiss sheet after successful save
//                editingSplit = false
//                editingContent = ""
//            } catch {
//                print("Failed to save new split day: \(error)")
//            }
//        }
//    }
//    
//    private func removeSplitDay(offsets: IndexSet) {
//        withAnimation {
//            for index in offsets {
//                modelContext.delete(splitDays[index])
//            }
//            renumberSplitDays()
//            do {
//                try modelContext.save()
//            } catch {
//                print("Failed to save after deletion: \(error)")
//            }
//        }
//    }
//    private func moveSplitDay(from source: IndexSet, to destination: Int) {
//        var updated = splitDays
//        updated.move(fromOffsets: source, toOffset: destination)
//        
//        for (i, day) in updated.enumerated() {
//            day.order = i
//        }
//        try? modelContext.save()
//    }
//
//    
//    private func renumberSplitDays() {
//        for (i, day) in splitDays.enumerated() {
//            day.order = i
//        }
//    }
}

#Preview {
    NavigationStack {
        HomeView()
            .modelContainer(for: SplitDay.self, inMemory: true)
    }
}
