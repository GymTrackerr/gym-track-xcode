import SwiftUI
import SwiftData

struct HomeView: View {
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var hkManager: HealthKitManager

    @State private var openedSession: Session? = nil
    @State private var navigateToSession:Bool = false
    
    var body: some View {
        VStack {
            if let _ = userService.currentUser {
                if !navigateToSession { // hide home content when navigating
                    ScrollView {
                        VStack {
                                
                            HStack(spacing: 16) {
                                MetricCard(title: "Current Weight", value: String(hkManager.userWeight ?? 0.00), icon: "lock.fill")
                                
                                MetricCard(title: "Weekly Steps", value: String(hkManager.totalStepsWeek.rounded()), icon: "figure.walk.motion")
                            }
                            .padding(.horizontal)
                            
                            StepBarGraph()
                                .padding()
                                .glassEffect(in: .rect(cornerRadius: 16.0))
//                                .background(
//                                    RoundedRectangle(cornerRadius: 16)
//                                        .fill(Color(.systemBackground))
//                                        .shadow(color: .gray.opacity(0.2), radius: 4, x: 0, y: 2)
//                                )
                                .padding(.horizontal)
                            VStack {
                                SessionsView(openedSession: $openedSession)
                                    .onChange(of: openedSession) {
                                        if openedSession != nil {
                                            navigateToSession = true
                                        }
                                    }
                            }
                        }
                    }
                }
            } else {
                Text("Please continue to onboarding")
            }
        }
        .task {
            await hkManager.requestAuthorization()
            await hkManager.fetchWeeklySteps()
            await hkManager.fetchUserWeight()
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
