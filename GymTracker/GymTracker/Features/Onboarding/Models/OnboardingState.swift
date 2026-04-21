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

    var subtitle: String {
        switch self {
        case .newToTraining:
            return "0-12 months"
        case .someExperience:
            return "1-3 years"
        case .experienced:
            return "3+ years"
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
            return "Generate a programme"
        case .existingRoutine:
            return "I already have my own routines"
        }
    }

    var subtitle: String {
        switch self {
        case .generateRoutine:
            return "Start with recommended routines based on your goals and experience."
        case .existingRoutine:
            return "Build your own routines, add exercises to each one, then choose the programme schedule."
        }
    }
}

enum OnboardingProgressionChoice: String, CaseIterable, Identifiable {
    case recommended
    case notNow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recommended:
            return "Recommended"
        case .notNow:
            return "Not now"
        }
    }

    var subtitle: String {
        switch self {
        case .recommended:
            return "Use the default progression style GymTracker suggests for your goals."
        case .notNow:
            return "Leave progression off for now and set it up later."
        }
    }
}

enum OnboardingRecommendations {
    static func recommendedProgressionProfileName(for goals: Set<OnboardingGoal>) -> String {
        if goals.contains(.getStronger) {
            return "Load Progression"
        }
        if goals.contains(.buildMuscle) {
            return "Double Progression"
        }
        return "Volume Progression"
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
    case generateDays
    case generateSplit
    case existingMode
    case existingStructure
    case existingExercises
    case existingExerciseEditor(UUID)
    case existingSchedule
    case buildingPreview
    case planPreview
    case progression
    case healthPermissions
    case notificationPermissions
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
    case continueFromPlannerChoice
    case continueFromGenerateDays
    case continueFromGenerateSplit
    case continueFromExistingMode
    case continueFromExistingStructure
    case continueFromExistingExercises
    case editExistingRoutineExercises(UUID)
    case continueFromExistingSchedule
    case finishPlanPreviewPreparation
    case continueFromPlanPreview
    case selectProgressionChoice(OnboardingProgressionChoice)
    case continueFromProgression
    case continueFromHealthPermissions
}

struct OnboardingDraft: Equatable {
    var name: String = ""
    var loginUsername: String = ""
    var loginPassword: String = ""
    var goals: Set<OnboardingGoal> = []
    var experience: OnboardingExperienceLevel?
    var planChoice: OnboardingPlanChoice?
    var generatedDaysPerWeek: Int?
    var selectedRecommendationId: String?
    var existingMode: ProgramMode?
    var existingRoutineDays: [OnboardingRoutineDayDraft] = OnboardingRoutineFocus.defaultDrafts(for: 3)
    var existingWeekdays: [ProgramWeekday] = OnboardingRoutineFocus.defaultWeekdays(for: 3)
    var continuousTrainDays: Int = 3
    var continuousRestDays: Int = 1
    var planPreview: OnboardingPlanPreview?
    var savedProgramId: UUID?
    var progressionChoice: OnboardingProgressionChoice?
}
