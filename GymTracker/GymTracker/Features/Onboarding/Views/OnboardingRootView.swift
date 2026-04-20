import SwiftUI

struct OnboardingRootView: View {
    @EnvironmentObject private var userService: UserService
    @EnvironmentObject private var backendAuthService: BackendAuthService
    @EnvironmentObject private var exerciseService: ExerciseService
    @EnvironmentObject private var routineService: RoutineService
    @EnvironmentObject private var programService: ProgramService

    @StateObject private var coordinator = OnboardingCoordinator()

    var body: some View {
        Group {
            if let onboardingState = userService.onboardingState {
                content(for: onboardingState)
            } else {
                EmptyView()
            }
        }
        .appBackground()
        .onAppear {
            coordinator.configure(
                for: userService.onboardingState,
                currentUser: userService.currentUser
            )
        }
        .onChange(of: userService.onboardingState) { _, newValue in
            coordinator.configure(for: newValue, currentUser: userService.currentUser)
        }
    }
    
    @ViewBuilder
    private func content(for onboardingState: OnboardingState) -> some View {
        VStack(spacing: 0) {
            if showsBackButton {
                HStack {
                    Button(action: handleBackTapped) {
                        Label("Back", systemImage: "chevron.left")
                            .font(.headline)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
            }

            switch coordinator.screen {
            case .welcome:
                OnboardingWelcomeView(
                    onLogin: { coordinator.send(.chooseLogin) },
                    onJoin: { coordinator.send(.chooseJoin) }
                )

            case .login:
                OnboardingLoginView(
                    username: coordinator.draft.loginUsername,
                    password: coordinator.draft.loginPassword,
                    errorMessage: coordinator.loginErrorMessage,
                    onUsernameChange: coordinator.updateLoginUsername(_:),
                    onPasswordChange: coordinator.updateLoginPassword(_:),
                    onSubmit: performLogin
                )

            case .loginSyncing:
                OnboardingSyncingView()

            case .name:
                OnboardingNameView(
                    name: coordinator.draft.name,
                    onNameChange: coordinator.updateName(_:),
                    onSubmit: createJoinUser
                )

            case .goals:
                OnboardingGoalsView(
                    selectedGoals: coordinator.draft.goals,
                    onToggleGoal: coordinator.toggleGoal(_:),
                    onContinue: { coordinator.send(.continueFromGoals) }
                )

            case .experience:
                OnboardingExperienceView(
                    selectedExperience: coordinator.draft.experience,
                    onSelectExperience: coordinator.selectExperience(_:),
                    onContinue: { coordinator.send(.continueFromExperience) }
                )

            case .plannerChoice:
                OnboardingPlannerChoiceView(
                    selectedChoice: coordinator.draft.planChoice,
                    onSelectChoice: { coordinator.send(.selectPlanChoice($0)) }
                )

            case .permissions:
                OnboardingPermissionsStepView {
                    coordinator.send(.continueFromPermissions)
                }

            case .accountLink:
                OnboardingAccountLinkStepView {
                    coordinator.send(.continueFromAccountLink)
                }

            case .exerciseCatalog:
                OnboardingExerciseCatalogStepView {
                    coordinator.send(.continueFromExerciseCatalog)
                }

            case .final:
                OnboardingFinalStepView()
            }

            Spacer()
        }
        .onAppear {
            coordinator.configure(for: onboardingState, currentUser: userService.currentUser)
        }
    }

    private func createJoinUser() {
        let trimmedName = coordinator.draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if case .required(let userId)? = userService.onboardingState,
           let currentUser = userService.currentUser,
           currentUser.id == userId,
           currentUser.needsOnboarding {
            userService.renameCurrentUser(to: trimmedName)
            coordinator.send(.joinAccountCreated(userId: userId, name: trimmedName))
            return
        }

        guard let user = userService.addUser(text: trimmedName) else { return }
        coordinator.send(.joinAccountCreated(userId: user.id, name: user.name))
    }

    private func performLogin() {
        let trimmedUsername = coordinator.draft.loginUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty else { return }
        guard !coordinator.draft.loginPassword.isEmpty else { return }

        coordinator.send(.loginStarted)

        Task {
            if userService.currentUser == nil || isCreatingAccountFromWelcome {
                _ = userService.addUser(text: trimmedUsername)
            }

            do {
                _ = try await backendAuthService.loginInteract(
                    username: trimmedUsername,
                    password: coordinator.draft.loginPassword
                )
                _ = try? await backendAuthService.refreshCurrentSession()
                let currentBackendUser = try? await backendAuthService.fetchCurrentUser()

                if let resolvedName = resolvedAccountName(from: currentBackendUser) {
                    userService.renameCurrentUser(to: resolvedName)
                }

                exerciseService.sync()
                routineService.loadSplitDays()
                programService.loadPrograms()

                let hasTrainingSetup = !routineService.routines.isEmpty || !programService.programs.isEmpty
                coordinator.send(
                    .loginSucceeded(
                        hasTrainingSetup: hasTrainingSetup,
                        resolvedName: userService.currentUser?.name
                    )
                )
            } catch {
                coordinator.send(.loginFailed(loginErrorMessage(from: error)))
            }
        }
    }

    private func resolvedAccountName(from user: BackendMeResponseDTO?) -> String? {
        let displayName = user?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !displayName.isEmpty {
            return displayName
        }

        let username = user?.username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return username.isEmpty ? nil : username
    }

    private func loginErrorMessage(from error: Error) -> String {
        if let apiError = error as? APIHelperError {
            switch apiError {
            case .httpError(let statusCode, _, let message, let details):
                return message ?? details ?? "Request failed with status \(statusCode)."
            case .missingAccessToken:
                return "Missing access token. Please try again."
            case .invalidResponse:
                return "Invalid response from the backend."
            }
        }

        return error.localizedDescription
    }

    private var showsBackButton: Bool {
        coordinator.canGoBack || (coordinator.screen == .welcome && userService.canDismissOnboarding)
    }

    private var isCreatingAccountFromWelcome: Bool {
        if case .noAccount? = userService.onboardingState {
            return true
        }
        return false
    }

    private func handleBackTapped() {
        if coordinator.canGoBack {
            coordinator.send(.goBack)
            return
        }

        if coordinator.screen == .welcome && userService.canDismissOnboarding {
            userService.cancelNewAccountOnboarding()
        }
    }
}

private struct OnboardingWelcomeView: View {
    let onLogin: () -> Void
    let onJoin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 12) {
                Text("Welcome to GymTracker")
                    .font(.largeTitle.bold())

                Text("Start with your account, then we’ll guide you into the setup flow.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 16) {
                Button("Login", action: onLogin)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())

                Button("Join GymTracker", action: onJoin)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.14))
                    .foregroundStyle(.primary)
                    .clipShape(Capsule())
            }

            Spacer()
        }
        .padding(24)
    }
}

private struct OnboardingLoginView: View {
    let username: String
    let password: String
    let errorMessage: String?
    let onUsernameChange: (String) -> Void
    let onPasswordChange: (String) -> Void
    let onSubmit: () -> Void

    private var isDisabled: Bool {
        username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Sign in")
                .font(.largeTitle.bold())

            Text("Use your Interact account to link and sync this GymTracker profile.")
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                TextField(
                    "Interact username",
                    text: Binding(get: { username }, set: onUsernameChange)
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .textFieldStyle(.roundedBorder)

                SecureField(
                    "Interact password",
                    text: Binding(get: { password }, set: onPasswordChange)
                )
                .textFieldStyle(.roundedBorder)
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Spacer()

            Button("Sign In", action: onSubmit)
                .disabled(isDisabled)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(Capsule())
        }
        .padding(24)
    }
}

private struct OnboardingSyncingView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Signing in and syncing your account...")
                .font(.headline)
            Text("We’ll route you into the right setup flow once that finishes.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(24)
    }
}

private struct OnboardingNameView: View {
    let name: String
    let onNameChange: (String) -> Void
    let onSubmit: () -> Void

    private var isDisabled: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("What’s your name?")
                .font(.largeTitle.bold())

            Text("We’ll use this for your local GymTracker profile.")
                .foregroundStyle(.secondary)

            TextField(
                "Name",
                text: Binding(get: { name }, set: onNameChange)
            )
            .textFieldStyle(.roundedBorder)

            Spacer()

            Button("Continue", action: onSubmit)
                .disabled(isDisabled)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(Capsule())
        }
        .padding(24)
    }
}

private struct OnboardingGoalsView: View {
    let selectedGoals: Set<OnboardingGoal>
    let onToggleGoal: (OnboardingGoal) -> Void
    let onContinue: () -> Void

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Your goals")
                    .font(.largeTitle.bold())

                Text("Pick up to two so we can shape the right setup flow.")
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(OnboardingGoal.allCases) { goal in
                        OnboardingSelectionCard(
                            title: goal.title,
                            subtitle: nil,
                            isSelected: selectedGoals.contains(goal),
                            action: { onToggleGoal(goal) }
                        )
                    }
                }

                Text("\(selectedGoals.count)/2 selected")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Continue", action: onContinue)
                    .disabled(selectedGoals.isEmpty)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .padding(24)
        }
    }
}

private struct OnboardingExperienceView: View {
    let selectedExperience: OnboardingExperienceLevel?
    let onSelectExperience: (OnboardingExperienceLevel) -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Training experience")
                .font(.largeTitle.bold())

            Text("This sets the tone for the setup flow and later recommendations.")
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                ForEach(OnboardingExperienceLevel.allCases) { experience in
                    OnboardingSelectionCard(
                        title: experience.title,
                        subtitle: nil,
                        isSelected: selectedExperience == experience,
                        action: { onSelectExperience(experience) }
                    )
                }
            }

            Spacer()

            Button("Continue", action: onContinue)
                .disabled(selectedExperience == nil)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(Capsule())
        }
        .padding(24)
    }
}

private struct OnboardingPlannerChoiceView: View {
    let selectedChoice: OnboardingPlanChoice?
    let onSelectChoice: (OnboardingPlanChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("How do you want to get started?")
                .font(.largeTitle.bold())

            Text("Choose the path you want. Routine setup starts from here in the next phase.")
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                ForEach(OnboardingPlanChoice.allCases) { choice in
                    OnboardingSelectionCard(
                        title: choice.title,
                        subtitle: choice.subtitle,
                        isSelected: selectedChoice == choice,
                        action: { onSelectChoice(choice) }
                    )
                }
            }

            if let selectedChoice {
                Text("Selected: \(selectedChoice.title)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Choose one to continue the setup flow.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(24)
    }
}

private struct OnboardingSelectionCard: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }

                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color.gray.opacity(0.10))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
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
