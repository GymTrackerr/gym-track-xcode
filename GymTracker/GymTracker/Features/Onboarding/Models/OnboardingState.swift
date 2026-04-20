import Foundation

enum UserOnboardingStatus: String, Codable {
    case pending
    case completed
}

enum OnboardingState: Equatable {
    case noAccount
    case required(userId: UUID)
}

enum OnboardingSetupStep: Int, CaseIterable {
    case permissions
    case accountLink
    case exerciseCatalog
    case final
}
