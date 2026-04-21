import SwiftData
import SwiftUI
#if os(iOS)
import UserNotifications
#endif

struct OnboardingRootView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var userService: UserService
    @EnvironmentObject private var backendAuthService: BackendAuthService
    @EnvironmentObject private var exerciseService: ExerciseService
    @EnvironmentObject private var routineService: RoutineService
    @EnvironmentObject private var programService: ProgramService
    @EnvironmentObject private var progressionService: ProgressionService
    @EnvironmentObject private var hkManager: HealthKitManager

    @StateObject private var coordinator = OnboardingCoordinator()
    @State private var templateBundle: OnboardingProgramTemplateBundle?
    @State private var templateLoadErrorMessage: String?
    @State private var isSavingPlan = false
    @State private var isRequestingHealthPermission = false
    @State private var isRequestingNotificationPermission = false

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
            loadTemplatesIfNeeded()
            progressionService.ensureBuiltInProfiles()
            progressionService.loadProfiles()
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
                    onSelectChoice: { coordinator.send(.selectPlanChoice($0)) },
                    onContinue: { coordinator.send(.continueFromPlannerChoice) }
                )

            case .generateDays:
                OnboardingGenerateDaysView(
                    selectedDaysPerWeek: coordinator.draft.generatedDaysPerWeek,
                    onSelectDays: { coordinator.updateGeneratedDays($0) },
                    onContinue: { coordinator.send(.continueFromGenerateDays) }
                )

            case .generateSplit:
                OnboardingGenerateSplitView(
                    recommendations: availableRecommendations,
                    selectedRecommendationId: selectedRecommendation?.id,
                    recommendedRecommendationId: recommendedRecommendation?.id,
                    templateLoadErrorMessage: templateLoadErrorMessage,
                    onSelectRecommendation: { coordinator.selectRecommendation($0) },
                    onContinue: beginGeneratePreviewPreparation
                )

            case .existingMode:
                OnboardingExistingModeView(
                    selectedMode: coordinator.draft.existingMode,
                    onSelectMode: { coordinator.selectExistingMode($0) },
                    onContinue: { coordinator.send(.continueFromExistingMode) }
                )

            case .existingStructure:
                OnboardingExistingStructureView(
                    routineDays: coordinator.draft.existingRoutineDays,
                    onUpdateDayCount: { coordinator.updateExistingDayCount($0) },
                    onSelectFocus: { focus, index in
                        coordinator.updateExistingFocus(focus, at: index)
                    },
                    onUpdateCustomName: { customName, index in
                        coordinator.updateExistingCustomName(customName, at: index)
                    },
                    onContinue: { coordinator.send(.continueFromExistingStructure) }
                )

            case .existingSchedule:
                OnboardingExistingScheduleView(
                    selectedMode: coordinator.draft.existingMode,
                    routineDays: coordinator.draft.existingRoutineDays,
                    selectedWeekdays: coordinator.draft.existingWeekdays,
                    trainDaysBeforeRest: coordinator.draft.continuousTrainDays,
                    restDays: coordinator.draft.continuousRestDays,
                    onUpdateWeekday: { weekday, index in
                        coordinator.updateExistingWeekday(weekday, at: index)
                    },
                    onUpdateTrainDays: { coordinator.updateContinuousTrainDays($0) },
                    onUpdateRestDays: { coordinator.updateContinuousRestDays($0) },
                    onContinue: beginExistingPreviewPreparation
                )

            case .buildingPreview:
                OnboardingBuildingPlanView(statusText: buildingPlanStatusText)

            case .planPreview:
                OnboardingPlanPreviewView(
                    preview: coordinator.draft.planPreview,
                    errorMessage: coordinator.planBuildErrorMessage,
                    isSaving: isSavingPlan,
                    onRetry: retryPlanPreviewPreparation,
                    onUsePlan: savePreparedPlan
                )

            case .progression:
                OnboardingProgressionStepView(
                    selectedChoice: coordinator.draft.progressionChoice,
                    recommendedProfileName: recommendedProgressionProfile?.name ?? recommendedProgressionProfileName,
                    recommendedDescription: recommendedProgressionProfile?.miniDescription ?? "A good default based on the goals you picked.",
                    onSelectChoice: { coordinator.send(.selectProgressionChoice($0)) },
                    onContinue: applyProgressionChoiceAndContinue
                )

            case .healthPermissions:
                OnboardingHealthPermissionsStepView(
                    isRequesting: isRequestingHealthPermission,
                    onAllow: requestHealthPermissionAndContinue,
                    onSkip: skipHealthPermissionAndContinue
                )

            case .notificationPermissions:
                OnboardingNotificationPermissionsStepView(
                    isRequesting: isRequestingNotificationPermission,
                    onAllow: requestNotificationPermissionAndFinish,
                    onSkip: skipNotificationPermissionAndFinish
                )
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

    private var planBuilder: OnboardingPlanBuilder {
        OnboardingPlanBuilder(context: context)
    }

    private var availableRecommendations: [OnboardingProgramTemplate] {
        guard let daysPerWeek = coordinator.draft.generatedDaysPerWeek else { return [] }
        let recommendations = templateBundle?.recommendations.filter { $0.daysPerWeek == daysPerWeek } ?? []
        guard let recommendedId = recommendedRecommendation?.id else { return recommendations }
        return recommendations.sorted { lhs, rhs in
            if lhs.id == recommendedId {
                return true
            }
            if rhs.id == recommendedId {
                return false
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private var selectedRecommendation: OnboardingProgramTemplate? {
        if let selectedRecommendationId = coordinator.draft.selectedRecommendationId,
           let selectedRecommendation = availableRecommendations.first(where: { $0.id == selectedRecommendationId }) {
            return selectedRecommendation
        }

        return recommendedRecommendation
    }

    private var recommendedRecommendation: OnboardingProgramTemplate? {
        guard let daysPerWeek = coordinator.draft.generatedDaysPerWeek else { return nil }

        let preferredId: String
        switch daysPerWeek {
        case 2:
            preferredId = "full-body-2"
        case 3:
            if coordinator.draft.experience == .experienced || coordinator.draft.goals.contains(.buildMuscle) {
                preferredId = "push-pull-legs-3"
            } else {
                preferredId = "full-body-3"
            }
        case 4:
            preferredId = "upper-lower-4"
        default:
            preferredId = "pplul-5"
        }

        return templateBundle?.recommendations.first(where: { $0.id == preferredId })
    }

    private var buildingPlanStatusText: String {
        let trimmedCatalogStatus = exerciseService.catalogSyncStatusText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCatalogStatus.isEmpty {
            return trimmedCatalogStatus
        }

        switch coordinator.draft.planChoice {
        case .generateRoutine:
            return "Preparing your routine..."
        case .existingRoutine:
            return "Preparing your preview..."
        case .none:
            return "Working..."
        }
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

    private func loadTemplatesIfNeeded() {
        guard templateBundle == nil else { return }

        do {
            templateBundle = try planBuilder.loadTemplates()
            templateLoadErrorMessage = nil
        } catch {
            templateLoadErrorMessage = error.localizedDescription
        }
    }

    private func beginGeneratePreviewPreparation() {
        loadTemplatesIfNeeded()

        guard let recommendation = selectedRecommendation else {
            coordinator.setPlanBuildError(templateLoadErrorMessage ?? OnboardingPlanBuilderError.missingTemplate.localizedDescription)
            coordinator.send(.finishPlanPreviewPreparation)
            return
        }

        coordinator.selectRecommendation(recommendation.id)
        coordinator.send(.continueFromGenerateSplit)

        Task {
            await preparePlanPreview()
        }
    }

    private func beginExistingPreviewPreparation() {
        coordinator.send(.continueFromExistingSchedule)

        Task {
            await preparePlanPreview()
        }
    }

    private func retryPlanPreviewPreparation() {
        switch coordinator.draft.planChoice {
        case .generateRoutine:
            coordinator.send(.continueFromGenerateSplit)
        case .existingRoutine:
            coordinator.send(.continueFromExistingSchedule)
        case .none:
            return
        }

        Task {
            await preparePlanPreview()
        }
    }

    private func preparePlanPreview() async {
        coordinator.setPlanPreview(nil)
        coordinator.setPlanBuildError(nil)

        do {
            switch coordinator.draft.planChoice {
            case .generateRoutine:
                loadTemplatesIfNeeded()

                if shouldAutoSyncCatalog {
                    exerciseService.setCatalogSyncEnabled(true)
                    await exerciseService.syncCatalogNow(force: true)
                }

                guard let recommendation = selectedRecommendation else {
                    throw OnboardingPlanBuilderError.missingTemplate
                }

                let preview = try planBuilder.prepareGeneratedPreview(
                    template: recommendation,
                    exercises: exerciseService.exercises
                )
                coordinator.setPlanPreview(preview)

            case .existingRoutine:
                let preview = try planBuilder.prepareExistingPreview(
                    name: existingPlanTitle,
                    mode: coordinator.draft.existingMode ?? .weekly,
                    routineDays: coordinator.draft.existingRoutineDays,
                    weeklyWeekdays: coordinator.draft.existingWeekdays,
                    trainDaysBeforeRest: coordinator.draft.continuousTrainDays,
                    restDays: coordinator.draft.continuousRestDays
                )
                coordinator.setPlanPreview(preview)

            case .none:
                return
            }
        } catch {
            coordinator.setPlanBuildError(error.localizedDescription)
        }

        coordinator.send(.finishPlanPreviewPreparation)
    }

    private func savePreparedPlan() {
        guard !isSavingPlan else { return }
        guard let preview = coordinator.draft.planPreview,
              let currentUser = userService.currentUser else {
            coordinator.setPlanBuildError(OnboardingPlanBuilderError.missingUser.localizedDescription)
            return
        }

        isSavingPlan = true
        coordinator.setPlanBuildError(nil)

        Task {
            defer { isSavingPlan = false }

            do {
                let program = try planBuilder.persist(preview: preview, for: currentUser)
                coordinator.setSavedProgramId(program.id)
                routineService.loadSplitDays()
                programService.loadPrograms()
                coordinator.send(.continueFromPlanPreview)
            } catch {
                coordinator.setPlanBuildError(error.localizedDescription)
            }
        }
    }

    private var shouldAutoSyncCatalog: Bool {
        let catalogExerciseCount = exerciseService.exercises.filter { exercise in
            !exercise.isArchived
            && exercise.isUserCreated == false
            && !(exercise.npId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }.count

        return catalogExerciseCount < 20
    }

    private var existingPlanTitle: String {
        let trimmedName = coordinator.draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return "\(trimmedName)'s Routine"
        }

        switch coordinator.draft.existingMode {
        case .continuous:
            return "Continuous Routine"
        case .weekly, .none:
            return "Weekly Routine"
        }
    }

    private var recommendedProgressionProfileName: String {
        OnboardingRecommendations.recommendedProgressionProfileName(for: coordinator.draft.goals)
    }

    private var recommendedProgressionProfile: ProgressionProfile? {
        progressionService.profiles.first(where: { $0.name == recommendedProgressionProfileName })
    }

    private var savedProgram: Program? {
        guard let savedProgramId = coordinator.draft.savedProgramId else { return nil }
        return programService.programs.first(where: { $0.id == savedProgramId })
            ?? programService.archivedPrograms.first(where: { $0.id == savedProgramId })
    }

    private func applyProgressionChoiceAndContinue() {
        progressionService.ensureBuiltInProfiles()
        progressionService.loadProfiles()

        let selectedProfile: ProgressionProfile?
        switch coordinator.draft.progressionChoice {
        case .recommended:
            selectedProfile = recommendedProgressionProfile
        case .notNow, .none:
            selectedProfile = nil
        }

        progressionService.saveGlobalDefaults(
            enabled: selectedProfile != nil,
            defaultProfileId: selectedProfile?.id
        )

        if let savedProgram {
            savedProgram.defaultProgressionProfileId = selectedProfile?.id
            savedProgram.defaultProgressionProfileNameSnapshot = selectedProfile?.name
            programService.saveChanges(for: savedProgram)
        }

        coordinator.send(.continueFromProgression)
    }

    private func requestHealthPermissionAndContinue() {
        guard !isRequestingHealthPermission else { return }
        isRequestingHealthPermission = true

        Task {
            await hkManager.requestAuthorization()
            userService.hkUserAllow(
                connected: hkManager.hkConnected,
                requested: hkManager.hkRequested
            )
            isRequestingHealthPermission = false
            coordinator.send(.continueFromHealthPermissions)
        }
    }

    private func skipHealthPermissionAndContinue() {
        userService.hkUserAllow(connected: false, requested: false)
        coordinator.send(.continueFromHealthPermissions)
    }

    private func requestNotificationPermissionAndFinish() {
        guard !isRequestingNotificationPermission else { return }
        isRequestingNotificationPermission = true

        Task {
            let granted = await requestNotificationAuthorization()
            applyNotificationDefaults(granted: granted)
            isRequestingNotificationPermission = false
            finishOnboarding()
        }
    }

    private func skipNotificationPermissionAndFinish() {
        applyNotificationDefaults(granted: false)
        finishOnboarding()
    }

    private func applyNotificationDefaults(granted: Bool) {
        userService.setTimerNotificationsEnabled(granted)
        userService.setTimerFinishedNotificationEnabled(granted)
        userService.setAwayTooLongEnabled(false)
    }

    private func finishOnboarding() {
        isRequestingHealthPermission = false
        isRequestingNotificationPermission = false
        userService.completeOnboarding()
    }

    private func requestNotificationAuthorization() async -> Bool {
        #if os(iOS)
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        #else
        return false
        #endif
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
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("How do you want to get started?")
                .font(.largeTitle.bold())

            Text("Choose the path you want, then we’ll shape the right setup flow.")
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

            Button("Continue", action: onContinue)
                .disabled(selectedChoice == nil)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(Capsule())
        }
        .padding(24)
    }
}

private struct OnboardingGenerateDaysView: View {
    let selectedDaysPerWeek: Int?
    let onSelectDays: (Int) -> Void
    let onContinue: () -> Void

    private let dayOptions = [2, 3, 4, 5]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("How many days each week?")
                .font(.largeTitle.bold())

            Text("We’ll use this to suggest a split that fits your schedule.")
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                ForEach(dayOptions, id: \.self) { dayCount in
                    let label = dayCount == 5 ? "5+" : "\(dayCount)"
                    let subtitle = dayCount == 2
                        ? "Low-friction starter split."
                        : dayCount == 3
                            ? "Balanced volume and recovery."
                            : dayCount == 4
                                ? "More structure for upper/lower work."
                                : "High-frequency training week."

                    OnboardingSelectionCard(
                        title: "\(label) days",
                        subtitle: subtitle,
                        isSelected: selectedDaysPerWeek == dayCount,
                        action: { onSelectDays(dayCount) }
                    )
                }
            }

            Spacer()

            Button("Continue", action: onContinue)
                .disabled(selectedDaysPerWeek == nil)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(Capsule())
        }
        .padding(24)
    }
}

private struct OnboardingGenerateSplitView: View {
    let recommendations: [OnboardingProgramTemplate]
    let selectedRecommendationId: String?
    let recommendedRecommendationId: String?
    let templateLoadErrorMessage: String?
    let onSelectRecommendation: (String) -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Suggested split")
                .font(.largeTitle.bold())

            Text("Choose the setup you want to preview.")
                .foregroundStyle(.secondary)

            if let templateLoadErrorMessage, recommendations.isEmpty {
                Text(templateLoadErrorMessage)
                    .foregroundStyle(.red)
            } else {
                VStack(spacing: 12) {
                    ForEach(recommendations, id: \.id) { recommendation in
                        OnboardingSelectionCard(
                            title: recommendation.title,
                            subtitle: subtitle(for: recommendation),
                            isSelected: isSelected(recommendation),
                            action: { onSelectRecommendation(recommendation.id) }
                        )
                    }
                }
            }

            Spacer()

            Button("Preview Routine", action: onContinue)
                .disabled(selectedRecommendationId == nil)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(Capsule())
        }
        .padding(24)
    }

    private func subtitle(for recommendation: OnboardingProgramTemplate) -> String {
        if isRecommended(recommendation) {
            return "Recommended: \(recommendation.subtitle)"
        }

        return recommendation.subtitle
    }

    private func isRecommended(_ recommendation: OnboardingProgramTemplate) -> Bool {
        guard let recommendedRecommendationId else { return false }
        return recommendedRecommendationId == recommendation.id
    }

    private func isSelected(_ recommendation: OnboardingProgramTemplate) -> Bool {
        guard let selectedRecommendationId else { return false }
        return selectedRecommendationId == recommendation.id
    }
}

private struct OnboardingExistingModeView: View {
    let selectedMode: ProgramMode?
    let onSelectMode: (ProgramMode) -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Routine type")
                .font(.largeTitle.bold())

            Text("Choose whether your schedule repeats by weekdays or rotates continuously.")
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                OnboardingSelectionCard(
                    title: "Weekly",
                    subtitle: "Example: Monday, Wednesday, Friday.",
                    isSelected: selectedMode == .weekly,
                    action: { onSelectMode(.weekly) }
                )

                OnboardingSelectionCard(
                    title: "Continuous",
                    subtitle: "Example: 3 days on, 1 day off.",
                    isSelected: selectedMode == .continuous,
                    action: { onSelectMode(.continuous) }
                )
            }

            Spacer()

            Button("Continue", action: onContinue)
                .disabled(selectedMode == nil)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(Capsule())
        }
        .padding(24)
    }
}

private struct OnboardingExistingStructureView: View {
    let routineDays: [OnboardingRoutineDayDraft]
    let onUpdateDayCount: (Int) -> Void
    let onSelectFocus: (OnboardingRoutineFocus, Int) -> Void
    let onUpdateCustomName: (String, Int) -> Void
    let onContinue: () -> Void

    private let dayOptions = [2, 3, 4, 5]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Build your structure")
                    .font(.largeTitle.bold())

                Text("Set the number of training days and choose a focus for each one.")
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    ForEach(dayOptions, id: \.self) { dayCount in
                        let isSelected = routineDays.count == dayCount
                        Button {
                            onUpdateDayCount(dayCount)
                        } label: {
                            Text(dayCount == 5 ? "5+" : "\(dayCount)")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(isSelected ? Color.accentColor.opacity(0.16) : Color.gray.opacity(0.10))
                                .foregroundStyle(.primary)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(spacing: 16) {
                    ForEach(Array(routineDays.enumerated()), id: \.element.id) { index, routineDay in
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Day \(index + 1)")
                                .font(.headline)

                            Picker(
                                "Focus",
                                selection: Binding(
                                    get: { routineDay.focus },
                                    set: { onSelectFocus($0, index) }
                                )
                            ) {
                                ForEach(OnboardingRoutineFocus.allCases) { focus in
                                    Text(focus.title).tag(focus)
                                }
                            }
                            .pickerStyle(.menu)

                            if routineDay.focus == .custom {
                                TextField(
                                    "Custom name",
                                    text: Binding(
                                        get: { routineDay.customName },
                                        set: { onUpdateCustomName($0, index) }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                }

                Button("Continue", action: onContinue)
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

private struct OnboardingExistingScheduleView: View {
    let selectedMode: ProgramMode?
    let routineDays: [OnboardingRoutineDayDraft]
    let selectedWeekdays: [ProgramWeekday]
    let trainDaysBeforeRest: Int
    let restDays: Int
    let onUpdateWeekday: (ProgramWeekday, Int) -> Void
    let onUpdateTrainDays: (Int) -> Void
    let onUpdateRestDays: (Int) -> Void
    let onContinue: () -> Void

    private var hasUniqueWeekdays: Bool {
        selectedWeekdays.count == routineDays.count && Set(selectedWeekdays.map(\.rawValue)).count == selectedWeekdays.count
    }

    private var canContinue: Bool {
        switch selectedMode {
        case .weekly:
            return hasUniqueWeekdays
        case .continuous:
            return trainDaysBeforeRest > 0
        case .none:
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Schedule")
                .font(.largeTitle.bold())

            if selectedMode == .weekly {
                Text("Pick the weekday for each routine.")
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    ForEach(Array(routineDays.enumerated()), id: \.element.id) { index, routineDay in
                        HStack {
                            Text(routineDay.preferredName)
                                .font(.headline)

                            Spacer()

                            Picker(
                                "Weekday",
                                selection: Binding(
                                    get: { selectedWeekdays[safe: index] ?? .monday },
                                    set: { onUpdateWeekday($0, index) }
                                )
                            ) {
                                ForEach(ProgramWeekday.allCases) { weekday in
                                    Text(weekday.title).tag(weekday)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        .padding(16)
                        .background(Color.gray.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                }

                if !hasUniqueWeekdays {
                    Text("Each routine needs its own weekday.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } else {
                Text("Set the rotation cadence for your routine.")
                    .foregroundStyle(.secondary)

                VStack(spacing: 16) {
                    Stepper(
                        "Training days before rest: \(trainDaysBeforeRest)",
                        value: Binding(get: { trainDaysBeforeRest }, set: onUpdateTrainDays),
                        in: 1...7
                    )

                    Stepper(
                        "Rest days: \(restDays)",
                        value: Binding(get: { restDays }, set: onUpdateRestDays),
                        in: 0...7
                    )

                    Text("Current cadence: \(trainDaysBeforeRest) on / \(restDays) off")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(Color.gray.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }

            Spacer()

            Button("Preview Routine", action: onContinue)
                .disabled(!canContinue)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(Capsule())
        }
        .padding(24)
    }
}

private struct OnboardingBuildingPlanView: View {
    let statusText: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text(statusText)
                .font(.headline)
            Text("This only takes a moment.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
    }
}

private struct OnboardingPlanPreviewView: View {
    let preview: OnboardingPlanPreview?
    let errorMessage: String?
    let isSaving: Bool
    let onRetry: () -> Void
    let onUsePlan: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let preview {
                    Text("Preview")
                        .font(.largeTitle.bold())

                    VStack(alignment: .leading, spacing: 8) {
                        Text(preview.title)
                            .font(.title.bold())

                        Text(preview.subtitle)
                            .foregroundStyle(.secondary)

                        Text(preview.scheduleSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 16) {
                        ForEach(preview.routines) { routine in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(routine.name)
                                        .font(.headline)

                                    Spacer()

                                    if let weekdayIndex = routine.weekdayIndex,
                                       let weekday = ProgramWeekday(rawValue: weekdayIndex) {
                                        Text(weekday.shortTitle)
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.accentColor.opacity(0.16))
                                            .clipShape(Capsule())
                                    }
                                }

                                if let focusLabel = routine.focusLabel, !focusLabel.isEmpty {
                                    Text(focusLabel)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }

                                if routine.exercises.isEmpty {
                                    Text("Exercises can be filled in later inside the app.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(routine.exercises) { exercise in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(exercise.name)
                                                .font(.subheadline.weight(.semibold))
                                            Text(exercise.detail)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                    }

                    Button(isSaving ? "Saving..." : "Use This Routine", action: onUsePlan)
                        .disabled(isSaving)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                } else if let errorMessage {
                    Text("Couldn’t build preview")
                        .font(.largeTitle.bold())

                    Text(errorMessage)
                        .foregroundStyle(.secondary)

                    Button("Try Again", action: onRetry)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }

                Spacer()
            }
            .padding(24)
        }
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

private struct OnboardingProgressionStepView: View {
    let selectedChoice: OnboardingProgressionChoice?
    let recommendedProfileName: String
    let recommendedDescription: String
    let onSelectChoice: (OnboardingProgressionChoice) -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Progression setup")
                .font(.largeTitle.bold())

            Text("Pick how GymTracker should guide progression once your routine is ready.")
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                OnboardingSelectionCard(
                    title: "Recommended",
                    subtitle: "\(recommendedProfileName): \(recommendedDescription)",
                    isSelected: selectedChoice == .recommended,
                    action: { onSelectChoice(.recommended) }
                )

                OnboardingSelectionCard(
                    title: "Not now",
                    subtitle: "Keep progression off for now. You can turn it on later in settings or per routine.",
                    isSelected: selectedChoice == .notNow,
                    action: { onSelectChoice(.notNow) }
                )
            }

            Spacer()

            Button("Continue", action: onContinue)
                .disabled(selectedChoice == nil)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(Capsule())
        }
        .padding(24)
    }
}

private struct OnboardingHealthPermissionsStepView: View {
    let isRequesting: Bool
    let onAllow: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Apple Health")
                .font(.largeTitle.bold())

            Text("If you allow it, GymTracker can use Apple Health to give your training more context.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 20) {
                row("figure.walk", "Sync steps, activity, and workouts for trend context.")
                row("scalemass.fill", "Use your body weight when it is available.")
                row("waveform.path.ecg", "Keep health and training data closer together.")
            }

            Text("You can change this later in the Health app or Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()

            Button(isRequesting ? "Requesting..." : "Allow Apple Health", action: onAllow)
                .disabled(isRequesting)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(Capsule())

            Button("Not Now", action: onSkip)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray.opacity(0.14))
                .foregroundStyle(.primary)
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

private struct OnboardingNotificationPermissionsStepView: View {
    let isRequesting: Bool
    let onAllow: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Notifications")
                .font(.largeTitle.bold())

            Text("Notifications help GymTracker keep you on track without getting in the way.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 20) {
                row("timer", "Get timer-finished alerts while resting between sets.")
                row("bell.badge", "Enable gentle workout reminders later if you want them.")
                row("checkmark.circle", "Keep the onboarding setup lightweight and adjustable.")
            }

            Text("You can change notification settings later at any time.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()

            Button(isRequesting ? "Requesting..." : "Allow Notifications", action: onAllow)
                .disabled(isRequesting)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(Capsule())

            Button("Not Now", action: onSkip)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray.opacity(0.14))
                .foregroundStyle(.primary)
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
