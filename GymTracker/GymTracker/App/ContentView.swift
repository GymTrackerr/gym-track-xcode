//
//  ContentView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var timerService: TimerService
    @EnvironmentObject var userService: UserService
    
    @State var query: String = ""
    @State var localSelected:Int = 0
    @State var showingOnboarding = false
    
    @State var linkActive = false
    @State var selectedLink = -1
#if DEBUG
    @State private var showingDebugNotesImport = false
#endif

    var body: some View {
        TabView (selection: $localSelected) {
            Tab("Home", systemImage: "house", value: 0) {
                NavigationStack {
                    GlassEffectContainer {
                        HomeView()
                            .appBackground()
                            .navigationDestination(isPresented: $linkActive) {
                                TimerView()
                                    .appBackground()
                            }
                    }
                }
            }
            
            if userService.currentUser?.showNutritionTab ?? true {
                Tab("Nutrition", systemImage: "fork.knife", value: 3) {
                    NavigationStack {
                        NutritionDayView().appBackground()
                    }
                }
            }
            
            Tab("Sessions", systemImage: "list.bullet.rectangle", value: 2) {
                NavigationStack {
                    SessionsPageView()
                        .appBackground()
                }
            }
            
            Tab("Exercises", systemImage: "dumbbell", value: 1) {
                NavigationStack {
                    ExercisesView()
                        .appBackground()
                }
            }

            Tab("Programme", systemImage: "figure.walk.motion", value: 4) {
                NavigationStack {
                    ProgramsRootView()
                        .appBackground()
                }
            }
            /*
            if (localSelected == 1) {
                Tab("Search", systemImage: "magnifyingglass", value: 3, role: .search) {
                    NavigationStack {
                        SearchView(query: $query)
                            .searchable(text: $query)
                        
                    }
                }
            }
             */
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            timerService.appDidEnterBackground()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            timerService.appDidBecomeActive()
        }
        .onChange(of: userService.currentUser?.showNutritionTab ?? true) {
            if !(userService.currentUser?.showNutritionTab ?? true), localSelected == 3 {
                localSelected = 0
            }
        }

        //.searchable(text: $query)
        .tabBarMinimizeIfAvailable()
        //        }
        .onOpenURL { url in
            print("Received deep link: \(url)")
            linkActive = true
        }
        .onAppear {
#if DEBUG
            Task.detached(priority: .background) {
                DebugHarness.runAll()
            }
#endif
        }
#if false
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button {
                    showingDebugNotesImport = true
                } label: {
                    Label("Debug Notes Import", systemImage: "doc.text")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showingDebugNotesImport) {
            NotesImportView(currentUserId: userService.currentUser?.id)
        }
#endif
        // 4.

    }

}
extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, content: (Self) -> Content) -> some View {
        if condition {
            content(self)
        } else {
            self
        }
    }
}

extension View {
    @ViewBuilder func tabBarMinimizeIfAvailable() -> some View {
        if #available(iOS 26, *) {
            self
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabBarMinimizeBehavior(.onScrollUp)
        } else {
            self
        }
    }
}


struct OnBoardView: View {
    @EnvironmentObject var userService: UserService
    
    var body: some View {
        VStack {
            switch userService.onBoardingScreen {
            case 0:
                OnBoardScreen0()
            case 1:
                OnBoardScreenPermissions()
            case 2:
                OnBoardScreenAccountLink()
            case 3:
                OnBoardScreenExerciseCatalog()
            case 4:
                OnBoardScreenFinal()
            default:
                EmptyView()
            }
            Spacer()
        }
        .appBackground()
    }
}

struct OnBoardScreen0: View {
    @EnvironmentObject var userService: UserService
    @State var userName : String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Welcome to GymTracker")
                .font(Font.largeTitle)
                .foregroundColor(.primary)
                .padding()
            Text("Please enter your name to get started")
                .font(.title)
                .foregroundColor(.secondary)
                .padding()
            
            TextField("Name", text: $userName)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            
//            Button {
//                userService.addUser(text: userName)
//                userName = ""
//                userService.onBoardingScreen = 1
//            } label: {
//                Label("Submit", systemImage: "plus.circle")
//                    .font(.title2)
//                    .padding()
//            }
            Spacer()

            Button("Next"){
                userService.addUser(text: userName)
                userName = ""
                userService.onBoardingScreen = 1
//            } label: {
//                Label("Next", systemImage: "plus.circle")
//                    .disabled(userName.trimmingCharacters(in: .whitespaces).isEmpty)

            }
            .disabled(userName.trimmingCharacters(in: .whitespaces).isEmpty)

            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
        .padding(24)
    }
}

struct OnBoardScreenPermissions: View {
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var hkManager: HealthKitManager

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Allow Health access to power GymTracker features like:")
                .font(.largeTitle)
                .bold()

            VStack(alignment: .leading, spacing: 20) {
                row("scalemass.fill", "Auto-fill your current weight (if available)")
                row("figure.walk", "Show weekly activity like steps and trends")
                row("heart.fill", "Keep your training data alongside your health history")
            }

            Button("Allow Health Access") {
                Task {
                    await hkManager.requestAuthorization()
                    
                    userService.hkUserAllow(connected: hkManager.hkConnected, requested: hkManager.hkRequested)
                }
            }
            .buttonStyle(.borderedProminent)

            Text("We only request the data needed for these features. You can change access anytime in the Health app or Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Next") {
                userService.onBoardingScreen = 2
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
        .padding(24)
    }

    private func row(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)

            Text(text)
                .font(.body)
        }
    }
}

struct OnBoardScreenFinal: View {
    @EnvironmentObject var userService: UserService

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Welcome, \(userService.currentUser?.name ?? "")")
                .font(Font.largeTitle)
                .foregroundColor(.primary)
                .padding()
            Text("You are ready to start using GymTracker")
            Spacer()

            
            Button("Done") {
                userService.onBoardingScreen = 5
                userService.onBoarding = false
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
        .padding(24)

//        .appBackground()
    }
}

struct OnBoardScreenAccountLink: View {
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var backendAuthService: BackendAuthService

    private var isLinked: Bool {
        guard let accessToken = backendAuthService.sessionSnapshot?.accessToken else {
            return false
        }
        return accessToken.isEmpty == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Optional: Link Your Interact Account")
                .font(.largeTitle)
                .bold()

            Text("Linking enables cloud sync for supported data. You can skip this now and link later in Settings.")
                .foregroundStyle(.secondary)

            InteractAccountLinkCard()

            Spacer()

            Button(isLinked ? "Continue" : "Skip for Now") {
                userService.onBoardingScreen = 3
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
        .padding(24)
    }
}

struct OnBoardScreenExerciseCatalog: View {
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var exerciseService: ExerciseService
    @EnvironmentObject var healthKitDailyStore: HealthKitDailyStore
    @State private var shouldDownloadExerciseDB = true
    @State private var selectedHealthRange: HealthHistorySyncRange = .defaultSelection

    private var canSyncHealthHistory: Bool {
        userService.currentUser?.allowHealthAccess == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Exercise Library Download")
                .font(.largeTitle)
                .bold()

            Text("Download ExerciseDB now for faster browsing and offline thumbnails. This is optional and you can change it later in Settings.")
                .foregroundStyle(.secondary)

            Toggle("Download ExerciseDB in the background", isOn: $shouldDownloadExerciseDB)

            VStack(alignment: .leading, spacing: 12) {
                Text("Optional: Download Apple Health history now")
                    .font(.headline)

                Picker("History range", selection: $selectedHealthRange) {
                    ForEach(HealthHistorySyncRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.menu)

                Button {
                    guard let userId = userService.currentUser?.id.uuidString else { return }
                    Task(priority: .utility) {
                        _ = await healthKitDailyStore.fullRefreshHealthHistory(
                            userId: userId,
                            range: selectedHealthRange
                        )
                    }
                } label: {
                    Text(healthKitDailyStore.isBackfillingHistory ? "Downloading Health History..." : "Download Health History Now")
                }
                .buttonStyle(.bordered)
                .disabled(!canSyncHealthHistory || healthKitDailyStore.isBackfillingHistory)

                if healthKitDailyStore.isBackfillingHistory {
                    ProgressView(value: progressValue)
                    Text(healthKitDailyStore.backfillStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !canSyncHealthHistory {
                    Text("Enable Apple Health access first if you want to download history now.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Continue") {
                exerciseService.completeOnboardingCatalogChoice(downloadCatalog: shouldDownloadExerciseDB)
                userService.onBoardingScreen = 4
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
        .padding(24)
        .onAppear {
            selectedHealthRange = userService.currentHealthHistorySyncRange()
        }
        .onChange(of: userService.currentUser?.id) { _, _ in
            selectedHealthRange = userService.currentHealthHistorySyncRange()
        }
        .onChange(of: selectedHealthRange) { _, newValue in
            guard userService.currentUser?.isDemo != true else { return }
            userService.setCurrentHealthHistorySyncRange(newValue)
        }
    }

    private var progressValue: Double {
        guard healthKitDailyStore.backfillProgressTotal > 0 else { return 0 }
        return min(
            max(
                Double(healthKitDailyStore.backfillProgressCompleted) /
                Double(healthKitDailyStore.backfillProgressTotal),
                0
            ),
            1
        )
    }
}

struct AppBackground: View {
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.85, green: 0.1, blue: 0.1),//.red,
                Color.clear//gray.opacity(0.3)
            ]),
            startPoint: .top,
            endPoint: .bottom,
        )
        .frame(height: 400)
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
    }
}

extension View {
    func appBackground() -> some View {
        self.background(AppBackground())
    }
}
