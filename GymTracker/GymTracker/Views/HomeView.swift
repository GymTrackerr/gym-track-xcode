import SwiftUI
import SwiftData

struct HomeView: View {
    @EnvironmentObject var userService: UserService

    var body: some View {
        VStack {
            if (userService.currentUser != nil) {
                Text("Welcome \(userService.currentUser?.name ?? "Unknown")")
                Spacer()
            } else {
                Text("Welcome")
            }
        }
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: SettingsView()) {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var userService: UserService

    var body: some View {
        VStack {
            List {
                // Settings
                // Show Account
                Button {
                    userService.removeUser(id: userService.currentUser!.id)
                } label: {
                    Text("Delete Account")
                }
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
//                    exerciseService.editingExercise = true
                } label: {
//                    Label("Add Exercise", systemImage: "plus.circle")
                }
            }
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
