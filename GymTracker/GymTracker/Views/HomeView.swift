import SwiftUI
import SwiftData

struct HomeView: View {
    @EnvironmentObject var userService: UserService
    @State private var openedSession: Session? = nil
    @State private var navigateToSession:Bool = false
    
    var body: some View {
        VStack {
            if let _ = userService.currentUser {
                if !navigateToSession { // hide home content when navigating
//                    Text("Welcome \(currentUser.name)")
                    SessionsView(openedSession: $openedSession)
                    .onChange(of: openedSession) {
                        if openedSession != nil {
                            navigateToSession = true
                        }
                    }
                }
            } else {
                Text("Please continue to onboarding")
            }
        }
        .navigationDestination(isPresented: $navigateToSession) {
            Group {
                if let openedSession {
                    SingleSessionView(session: openedSession)
                } else {
                    EmptyView()
                }
            }
        }
        .navigationTitle(userService.currentUser != nil ? "Welcome \(userService.currentUser!.name)" : "Home" )
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: SettingsView()) {
                    Label("Settings", systemImage: "gearshape")
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
