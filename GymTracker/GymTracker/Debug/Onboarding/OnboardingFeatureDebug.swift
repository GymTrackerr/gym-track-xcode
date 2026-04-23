#if DEBUG
import Foundation

final class OnboardingFeatureDebug {
    static func runSamples() {
        print("=== OnboardingFeatureDebug start ===")
        let results = [
            check(
                label: "onboarding-progression-strength",
                actual: OnboardingRecommendations.recommendedProgressionProfileName(for: [.getStronger]),
                expected: "Load Progression"
            ),
            check(
                label: "onboarding-progression-hypertrophy",
                actual: OnboardingRecommendations.recommendedProgressionProfileName(for: [.buildMuscle]),
                expected: "Double Progression"
            ),
            check(
                label: "onboarding-progression-default",
                actual: OnboardingRecommendations.recommendedProgressionProfileName(for: [.generalFitness]),
                expected: "Volume Progression"
            )
        ]

        let passCount = results.filter { $0 }.count
        print("=== OnboardingFeatureDebug done: \(passCount)/\(results.count) passed ===")
    }

    @discardableResult
    private static func check(label: String, actual: String, expected: String) -> Bool {
        let ok = actual == expected
        print("[\(label)] \(ok ? "PASS" : "FAIL") expected=\(expected) actual=\(actual)")
        return ok
    }
}
#endif
