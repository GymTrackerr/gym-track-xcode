//
//  OnboardingCoordinator.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2026-04-20.
//


import Combine
import Foundation

@MainActor
final class OnboardingCoordinator: ObservableObject {
    private enum FlowOrigin: Equatable {
        case login
        case join
        case existingPending
    }

    @Published private(set) var screen: OnboardingScreen = .welcome
    @Published private(set) var draft = OnboardingDraft()
    @Published private(set) var loginErrorMessage: String?
    @Published private(set) var planBuildErrorMessage: String?

    private var activeUserId: UUID?
    private var flowOrigin: FlowOrigin?

    var canGoBack: Bool {
        previousScreen() != nil
    }

    func configure(for onboardingState: OnboardingState?, currentUser: User?) {
        guard let onboardingState else {
            return
        }

        switch onboardingState {
        case .noAccount:
            activeUserId = nil
            if screen != .welcome && screen != .login && screen != .name {
                draft = OnboardingDraft()
                loginErrorMessage = nil
                planBuildErrorMessage = nil
                flowOrigin = nil
                screen = .welcome
            }

        case .required(let userId):
            if screen == .name || screen == .login || screen == .loginSyncing {
                activeUserId = userId
                if draft.name.isEmpty {
                    draft.name = currentUser?.name ?? ""
                }
                return
            }

            guard activeUserId != userId else {
                if draft.name.isEmpty {
                    draft.name = currentUser?.name ?? ""
                }
                return
            }

            activeUserId = userId
            draft.name = currentUser?.name ?? draft.name
            if flowOrigin == nil {
                flowOrigin = .existingPending
            }
            if screen == .welcome {
                screen = .goals
            }
            loginErrorMessage = nil
        }
    }

    func updateName(_ name: String) {
        draft.name = name
    }

    func updateLoginUsername(_ username: String) {
        draft.loginUsername = username
    }

    func updateLoginPassword(_ password: String) {
        draft.loginPassword = password
    }

    func toggleGoal(_ goal: OnboardingGoal) {
        if draft.goals.contains(goal) {
            draft.goals.remove(goal)
            return
        }

        guard draft.goals.count < 2 else { return }
        draft.goals.insert(goal)
    }

    func selectExperience(_ experience: OnboardingExperienceLevel) {
        draft.experience = experience
    }

    func updateGeneratedDays(_ daysPerWeek: Int) {
        draft.generatedDaysPerWeek = daysPerWeek
        draft.selectedRecommendationId = nil
        clearPlanPreview()
    }

    func selectRecommendation(_ recommendationId: String) {
        draft.selectedRecommendationId = recommendationId
        clearPlanPreview()
    }

    func selectExistingMode(_ mode: ProgramMode) {
        draft.existingMode = mode
        clearPlanPreview()
    }

    func updateExistingDayCount(_ dayCount: Int) {
        let sanitizedDayCount = max(2, min(dayCount, 5))
        draft.existingRoutineDays = OnboardingRoutineFocus.defaultDrafts(for: sanitizedDayCount)
        draft.existingWeekdays = OnboardingRoutineFocus.defaultWeekdays(for: sanitizedDayCount)
        clearPlanPreview()
    }

    func updateExistingFocus(_ focus: OnboardingRoutineFocus, at index: Int) {
        guard draft.existingRoutineDays.indices.contains(index) else { return }
        draft.existingRoutineDays[index].focus = focus
        if focus != .custom, draft.existingRoutineDays[index].customName == "Custom" {
            draft.existingRoutineDays[index].customName = ""
        }
        clearPlanPreview()
    }

    func updateExistingCustomName(_ customName: String, at index: Int) {
        guard draft.existingRoutineDays.indices.contains(index) else { return }
        draft.existingRoutineDays[index].customName = customName
        clearPlanPreview()
    }

    func updateExistingWeekday(_ weekday: ProgramWeekday, at index: Int) {
        guard draft.existingWeekdays.indices.contains(index) else { return }
        draft.existingWeekdays[index] = weekday
        clearPlanPreview()
    }

    func updateContinuousTrainDays(_ value: Int) {
        draft.continuousTrainDays = max(1, min(value, 7))
        clearPlanPreview()
    }

    func updateContinuousRestDays(_ value: Int) {
        draft.continuousRestDays = max(0, min(value, 7))
        clearPlanPreview()
    }

    func setPlanPreview(_ preview: OnboardingPlanPreview?) {
        draft.planPreview = preview
        if preview != nil {
            planBuildErrorMessage = nil
        }
    }

    func setSavedProgramId(_ programId: UUID?) {
        draft.savedProgramId = programId
    }

    func setPlanBuildError(_ message: String?) {
        planBuildErrorMessage = message
        if message != nil {
            draft.planPreview = nil
        }
    }

    func send(_ event: OnboardingEvent) {
        switch event {
        case .goBack:
            guard let previousScreen = previousScreen() else { return }
            if previousScreen == .welcome {
                loginErrorMessage = nil
            }
            screen = previousScreen

        case .chooseLogin:
            flowOrigin = .login
            loginErrorMessage = nil
            clearPlanPreview()
            screen = .login

        case .chooseJoin:
            flowOrigin = .join
            loginErrorMessage = nil
            clearPlanPreview()
            screen = .name

        case .loginStarted:
            loginErrorMessage = nil
            planBuildErrorMessage = nil
            screen = .loginSyncing

        case .loginSucceeded(let hasTrainingSetup, let resolvedName):
            if let resolvedName, !resolvedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.name = resolvedName
            }
            draft.loginPassword = ""
            loginErrorMessage = nil
            screen = hasTrainingSetup ? .healthPermissions : .goals

        case .loginFailed(let message):
            loginErrorMessage = message
            screen = .login

        case .joinAccountCreated(let userId, let name):
            activeUserId = userId
            draft.name = name
            flowOrigin = .join
            screen = .goals

        case .continueFromGoals:
            guard !draft.goals.isEmpty else { return }
            screen = .experience

        case .continueFromExperience:
            guard draft.experience != nil else { return }
            screen = .plannerChoice

        case .selectPlanChoice(let choice):
            draft.planChoice = choice
            clearPlanPreview()

        case .continueFromPlannerChoice:
            guard let planChoice = draft.planChoice else { return }
            clearPlanPreview()
            switch planChoice {
            case .generateRoutine:
                if draft.generatedDaysPerWeek == nil {
                    draft.generatedDaysPerWeek = 3
                }
                screen = .generateDays
            case .existingRoutine:
                screen = .existingMode
            }

        case .continueFromGenerateDays:
            guard draft.generatedDaysPerWeek != nil else { return }
            screen = .generateSplit

        case .continueFromGenerateSplit:
            guard draft.selectedRecommendationId != nil else { return }
            planBuildErrorMessage = nil
            draft.planPreview = nil
            screen = .buildingPreview

        case .continueFromExistingMode:
            guard draft.existingMode != nil else { return }
            screen = .existingStructure

        case .continueFromExistingStructure:
            guard !draft.existingRoutineDays.isEmpty else { return }
            screen = .existingSchedule

        case .continueFromExistingSchedule:
            guard draft.existingMode != nil else { return }
            planBuildErrorMessage = nil
            draft.planPreview = nil
            screen = .buildingPreview

        case .finishPlanPreviewPreparation:
            screen = .planPreview

        case .continueFromPlanPreview:
            guard draft.planPreview != nil else { return }
            if draft.progressionChoice == nil {
                draft.progressionChoice = .recommended
            }
            screen = .progression

        case .selectProgressionChoice(let choice):
            draft.progressionChoice = choice

        case .continueFromProgression:
            guard draft.progressionChoice != nil else { return }
            screen = .healthPermissions

        case .continueFromHealthPermissions:
            screen = .notificationPermissions
        }
    }

    private func previousScreen() -> OnboardingScreen? {
        switch screen {
        case .welcome:
            return nil

        case .login:
            return .welcome

        case .loginSyncing:
            return nil

        case .name:
            return .welcome

        case .goals:
            switch flowOrigin {
            case .join:
                return .name
            case .login:
                return .login
            case .existingPending, .none:
                return nil
            }

        case .experience:
            return .goals

        case .plannerChoice:
            return .experience

        case .generateDays:
            return .plannerChoice

        case .generateSplit:
            return .generateDays

        case .existingMode:
            return .plannerChoice

        case .existingStructure:
            return .existingMode

        case .existingSchedule:
            return .existingStructure

        case .buildingPreview:
            return nil

        case .planPreview:
            switch draft.planChoice {
            case .generateRoutine:
                return .generateSplit
            case .existingRoutine:
                return .existingSchedule
            case .none:
                return .plannerChoice
            }

        case .progression:
            return .planPreview

        case .healthPermissions:
            if draft.savedProgramId != nil || draft.progressionChoice != nil {
                return .progression
            }
            return nil

        case .notificationPermissions:
            return .healthPermissions
        }
    }

    private func clearPlanPreview() {
        draft.planPreview = nil
        draft.savedProgramId = nil
        draft.progressionChoice = nil
        planBuildErrorMessage = nil
    }
}
