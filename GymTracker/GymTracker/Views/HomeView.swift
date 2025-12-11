import SwiftUI
import SwiftData

struct HomeView: View {
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var timerService: TimerService
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
                                MetricCard(
                                    title: "Current Weight",
                                    value: String(hkManager.userWeight ?? 0.00),
                                    icon: "lock.fill")
                                
                                MetricCard(
                                    title: "Weekly Steps",
                                    value: String(hkManager.totalStepsWeek.rounded()),
                                    icon: "figure.walk.motion")
                            }
                            .padding(.horizontal)
                            
                            if let previousSleepNight = hkManager.sleepData.first?.duration {
                                let sleepHours = previousSleepNight / 3600
                                HStack(spacing: 16) {
                                    MetricCard(
                                        title: "Sleep",
                                        value: String(format: "%.1f", sleepHours)+" hrs",
                                        icon: "bed.double",
                                        alignment: .center
                                    )
                                }
                                .padding(.horizontal)
                            }
                            
                            if let ars = hkManager.activityRingStatus {
                                HStack(spacing: 16) {
                                    MetricActivityRingCard(
                                        title: "Activity Rings",
                                        activityRings: ars,
                                        alignment: .center
                                    )
                                }
                                .padding(.horizontal)
                            }
                            HStack(spacing: 16) {
                                NavigationLink(destination:
                                    TimerView()
                                    .appBackground()
                                ) {
                                    MetricCard(
                                        title: timerService.timer != nil ? "Timer" : "Start Timer",
                                        value: timerService.timer != nil ? timerService.formatted : "--:--",
                                        icon: "timer",
                                        pageNav: true
//                                        alignment: .center
                                    )
                                }
//                            }
//                            .padding(.horizontal)
//                            
//                            HStack(spacing: 16) {
                                NavigationLink(destination:
                                    HealthWorkoutView()
                                    .appBackground()
                                ) {
                                    MetricCard(
                                        title: "Fitness Workouts",
                                        value: String(hkManager.workouts.count),
                                        icon: "figure.strengthtraining.traditional",
                                        pageNav: true
//                                        alignment: .center
                                    )
                                }
                            }
                            .padding(.horizontal)
                            
                            StepBarGraph()
                                .padding()
                                .glassEffect(in: .rect(cornerRadius: 16.0))
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
            await hkManager.fetchWorkouts()
//            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
            await hkManager.fetchActivityRingStatus()//for: yesterday)
            await hkManager.fetchSleepData()

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
