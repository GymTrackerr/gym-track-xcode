import Foundation

enum UserOnboardingStatus: String, Codable {
    case pending
    case completed
}

enum OnboardingState: Equatable {
    case noAccount
    case required(userId: UUID)
}

enum OnboardingGoal: String, CaseIterable, Identifiable, Hashable {
    case loseWeight
    case buildMuscle
    case getStronger
    case generalFitness
    case casualTracking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .loseWeight:
            return "Lose weight"
        case .buildMuscle:
            return "Build muscle"
        case .getStronger:
            return "Get stronger"
        case .generalFitness:
            return "General fitness"
        case .casualTracking:
            return "Casual tracking"
        }
    }
}

enum OnboardingExperienceLevel: String, CaseIterable, Identifiable {
    case newToTraining
    case someExperience
    case experienced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newToTraining:
            return "New to training"
        case .someExperience:
            return "Some experience"
        case .experienced:
            return "Experienced"
        }
    }
}

enum OnboardingPlanChoice: String, CaseIterable, Identifiable {
    case generateRoutine
    case existingRoutine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generateRoutine:
            return "Generate a routine"
        case .existingRoutine:
            return "I already have my own"
        }
    }

    var subtitle: String {
        switch self {
        case .generateRoutine:
            return "Start with recommendations based on your goals and experience."
        case .existingRoutine:
            return "Set up your own structure and schedule in the next step."
        }
    }
}

enum OnboardingScreen: Equatable {
    case welcome
    case login
    case loginSyncing
    case name
    case goals
    case experience
    case plannerChoice
    case permissions
    case accountLink
    case exerciseCatalog
    case final
}

enum OnboardingEvent {
    case goBack
    case chooseLogin
    case chooseJoin
    case loginStarted
    case loginSucceeded(hasTrainingSetup: Bool, resolvedName: String?)
    case loginFailed(String)
    case joinAccountCreated(userId: UUID, name: String)
    case continueFromGoals
    case continueFromExperience
    case selectPlanChoice(OnboardingPlanChoice)
    case continueFromPermissions
    case continueFromAccountLink
    case continueFromExerciseCatalog
}

struct OnboardingDraft: Equatable {
    var name: String = ""
    var loginUsername: String = ""
    var loginPassword: String = ""
    var goals: Set<OnboardingGoal> = []
    var experience: OnboardingExperienceLevel?
    var planChoice: OnboardingPlanChoice?
}
