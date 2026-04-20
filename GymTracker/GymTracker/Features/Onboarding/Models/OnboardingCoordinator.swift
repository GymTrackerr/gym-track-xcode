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
            screen = .goals
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
            screen = .login

        case .chooseJoin:
            flowOrigin = .join
            loginErrorMessage = nil
            screen = .name

        case .loginStarted:
            loginErrorMessage = nil
            screen = .loginSyncing

        case .loginSucceeded(let hasTrainingSetup, let resolvedName):
            if let resolvedName, !resolvedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.name = resolvedName
            }
            draft.loginPassword = ""
            loginErrorMessage = nil
            screen = hasTrainingSetup ? .permissions : .goals

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

        case .continueFromPermissions:
            screen = .accountLink

        case .continueFromAccountLink:
            screen = .exerciseCatalog

        case .continueFromExerciseCatalog:
            screen = .final
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

        case .permissions:
            if draft.planChoice != nil {
                return .plannerChoice
            }
            if draft.experience != nil {
                return .experience
            }
            if draft.goals.isEmpty == false {
                return .goals
            }
            if flowOrigin == .login {
                return .login
            }
            return nil

        case .accountLink:
            return .permissions

        case .exerciseCatalog:
            return .accountLink

        case .final:
            return .exerciseCatalog
        }
    }
}
