import SwiftUI

struct OnboardingRootView: View {
    @EnvironmentObject private var userService: UserService

    var body: some View {
        Group {
            if let onboardingState = userService.onboardingState {
                VStack {
                    switch onboardingState {
                    case .noAccount:
                        OnboardingProfileEntryView()
                    case .required:
                        OnboardingSetupFlowView()
                    }

                    Spacer()
                }
            } else {
                EmptyView()
            }
        }
        .appBackground()
    }
}

private struct OnboardingProfileEntryView: View {
    @EnvironmentObject private var userService: UserService
    @State private var userName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Welcome to GymTracker")
                .font(.largeTitle)
                .foregroundColor(.primary)
                .padding()

            Text("Please enter your name to get started")
                .font(.title)
                .foregroundColor(.secondary)
                .padding()

            TextField("Name", text: $userName)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            Spacer()

            Button("Next") {
                userService.addUser(text: userName)
                userName = ""
            }
            .disabled(userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
        .padding(24)
    }
}

private struct OnboardingSetupFlowView: View {
    @State private var step: OnboardingSetupStep = .permissions

    var body: some View {
        switch step {
        case .permissions:
            OnboardingPermissionsStepView {
                step = .accountLink
            }
        case .accountLink:
            OnboardingAccountLinkStepView {
                step = .exerciseCatalog
            }
        case .exerciseCatalog:
            OnboardingExerciseCatalogStepView {
                step = .final
            }
        case .final:
            OnboardingFinalStepView()
        }
    }
}

private struct OnboardingPermissionsStepView: View {
    @EnvironmentObject private var userService: UserService
    @EnvironmentObject private var hkManager: HealthKitManager

    let onNext: () -> Void

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
                    userService.hkUserAllow(
                        connected: hkManager.hkConnected,
                        requested: hkManager.hkRequested
                    )
                }
            }
            .buttonStyle(.borderedProminent)

            Text("We only request the data needed for these features. You can change access anytime in the Health app or Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Next", action: onNext)
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

private struct OnboardingAccountLinkStepView: View {
    @EnvironmentObject private var backendAuthService: BackendAuthService

    let onNext: () -> Void

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

            Button(isLinked ? "Continue" : "Skip for Now", action: onNext)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(Capsule())
        }
        .padding(24)
    }
}

private struct OnboardingExerciseCatalogStepView: View {
    @EnvironmentObject private var userService: UserService
    @EnvironmentObject private var exerciseService: ExerciseService
    @EnvironmentObject private var healthKitDailyStore: HealthKitDailyStore

    @State private var shouldDownloadExerciseDB = true
    @State private var selectedHealthRange: HealthHistorySyncRange = .defaultSelection

    let onNext: () -> Void

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
                    Text(
                        healthKitDailyStore.isBackfillingHistory
                        ? "Downloading Health History..."
                        : "Download Health History Now"
                    )
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
                onNext()
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

private struct OnboardingFinalStepView: View {
    @EnvironmentObject private var userService: UserService

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Welcome, \(userService.currentUser?.name ?? "")")
                .font(.largeTitle)
                .foregroundColor(.primary)
                .padding()

            Text("You are ready to start using GymTracker")

            Spacer()

            Button("Done") {
                userService.completeOnboarding()
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
