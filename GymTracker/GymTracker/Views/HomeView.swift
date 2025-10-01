import SwiftUI
import SwiftData

struct HomeView: View {

    var body: some View {
        VStack {
        }
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .modelContainer(for: SplitDay.self, inMemory: true)
            .modelContainer(for: Exercise.self, inMemory: true)
    }
}
