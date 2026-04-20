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
    @Published private(set) var screen: OnboardingScreen = .welcome
    @Published private(set) var draft = OnboardingDraft()
    @Published private(set) var loginErrorMessage: String?

    private var activeUserId: UUID?

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
        case .chooseLogin:
            loginErrorMessage = nil
            screen = .login

        case .chooseJoin:
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
}
