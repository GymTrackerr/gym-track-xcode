import Foundation

enum ModuleSize: String, Codable {
    case small = "1x1"
    case medium = "2x1"
    case large = "2x2"
    
    var displayName: String {
        String(localized: displayNameResource)
    }

    var displayNameResource: LocalizedStringResource {
        switch self {
        case .small:
            return LocalizedStringResource(
                "dashboard.moduleSize.small",
                defaultValue: "Small (1x1)",
                table: "Shared",
                comment: "Small dashboard module size option"
            )
        case .medium:
            return LocalizedStringResource(
                "dashboard.moduleSize.medium",
                defaultValue: "Medium (2x1)",
                table: "Shared",
                comment: "Medium dashboard module size option"
            )
        case .large:
            return LocalizedStringResource(
                "dashboard.moduleSize.large",
                defaultValue: "Large (2x2)",
                table: "Shared",
                comment: "Large dashboard module size option"
            )
        }
    }

    var columnSpan: Int {
        switch self {
        case .small:
            return 1
        case .medium, .large:
            return 2
        }
    }

    var rowSpan: Int {
        switch self {
        case .small, .medium:
            return 1
        case .large:
            return 2
        }
    }
}

enum ModuleType: String, Codable, CaseIterable {
    case currentWeight = "currentWeight"
    case weeklySteps = "weeklySteps"
    case sleep = "sleep"
    case activityRings = "activityRings"
    case timer = "timer"
    case fitnessWorkouts = "fitnessWorkouts"
    case truesight = "truesight"
    case nutrition = "nutrition"
    case sessionVolume = "sessionVolume"
    case program = "program"
    
    var displayName: String {
        String(localized: displayNameResource)
    }

    var displayNameResource: LocalizedStringResource {
        switch self {
        case .currentWeight:
            return LocalizedStringResource("dashboard.module.currentWeight", defaultValue: "Current Weight", table: "Shared")
        case .weeklySteps:
            return LocalizedStringResource("dashboard.module.weeklySteps", defaultValue: "Weekly Steps", table: "Shared")
        case .sleep:
            return LocalizedStringResource("dashboard.module.sleep", defaultValue: "Sleep", table: "Shared")
        case .activityRings:
            return LocalizedStringResource("dashboard.module.activityRings", defaultValue: "Activity Rings", table: "Shared")
        case .timer:
            return LocalizedStringResource("dashboard.module.timer", defaultValue: "Timer", table: "Shared")
        case .fitnessWorkouts:
            return LocalizedStringResource("dashboard.module.fitnessWorkouts", defaultValue: "Fitness Workouts", table: "Shared")
        case .truesight:
            return LocalizedStringResource("dashboard.module.truesight", defaultValue: "TrueSight", table: "Shared")
        case .nutrition:
            return LocalizedStringResource("dashboard.module.nutrition", defaultValue: "Nutrition", table: "Shared")
        case .sessionVolume:
            return LocalizedStringResource("dashboard.module.sessionVolume", defaultValue: "Session Volume", table: "Shared")
        case .program:
            return LocalizedStringResource("programme.term.programme", defaultValue: "Programme", table: "Programmes")
        }
    }
    
    var iconName: String {
        switch self {
        case .currentWeight: return "lock.fill"
        case .weeklySteps: return "figure.walk.motion"
        case .sleep: return "bed.double"
        case .activityRings: return "gauge.with.needle"
        case .timer: return "timer"
        case .fitnessWorkouts: return "figure.strengthtraining.traditional"
        case .truesight: return "video"
        case .nutrition: return "fork.knife"
        case .sessionVolume: return "chart.bar.xaxis"
        case .program: return "figure.strengthtraining.traditional"
        }
    }
    
    var allowedSizes: [ModuleSize] {
        switch self {
        case .currentWeight:
            return [.small]
        case .weeklySteps:
            return [.small, .medium, .large]
        case .sleep:
            return [.small, .medium, .large]
        case .timer:
            return [.small, .medium, .large]
        case .fitnessWorkouts:
            return [.small]
        case .activityRings:
            return [.medium, .large]
        case .truesight:
            return [.small]
        case .nutrition:
            return [.small, .medium, .large]
        case .sessionVolume:
            return [.small, .medium, .large]
        case .program:
            return [.small, .medium]
        }
    }

    var requiresHealthAccess: Bool {
        switch self {
        case .currentWeight, .weeklySteps, .sleep, .activityRings, .fitnessWorkouts:
            return true
        case .timer, .truesight, .nutrition, .sessionVolume, .program:
            return false
        }
    }
}

enum DashboardPreset: String, CaseIterable, Identifiable {
    case `default`
    case training
    case health
    case minimal
#if DEBUG
    case mixedCompact
    case mixedBalanced
    case wideStressTest
#endif

    var id: String { rawValue }

    static var productionCases: [DashboardPreset] {
        [.default, .training, .health, .minimal]
    }

#if DEBUG
    static var debugCases: [DashboardPreset] {
        [.mixedCompact, .mixedBalanced, .wideStressTest]
    }
#else
    static var debugCases: [DashboardPreset] {
        []
    }
#endif

    var displayName: String {
        String(localized: displayNameResource)
    }

    var displayNameResource: LocalizedStringResource {
        switch self {
        case .default:
            return LocalizedStringResource("dashboard.preset.default.title", defaultValue: "Default", table: "Shared")
        case .training:
            return LocalizedStringResource("dashboard.preset.training.title", defaultValue: "Training", table: "Shared")
        case .health:
            return LocalizedStringResource("dashboard.preset.health.title", defaultValue: "Health", table: "Shared")
        case .minimal:
            return LocalizedStringResource("dashboard.preset.minimal.title", defaultValue: "Minimal", table: "Shared")
#if DEBUG
        case .mixedCompact:
            return LocalizedStringResource("dashboard.preset.mixedCompact.title", defaultValue: "Mixed Compact", table: "Shared")
        case .mixedBalanced:
            return LocalizedStringResource("dashboard.preset.mixedBalanced.title", defaultValue: "Mixed Balanced", table: "Shared")
        case .wideStressTest:
            return LocalizedStringResource("dashboard.preset.wideStressTest.title", defaultValue: "Wide Stress Test", table: "Shared")
#endif
        }
    }

    var description: String {
        String(localized: descriptionResource)
    }

    var descriptionResource: LocalizedStringResource {
        switch self {
        case .default:
            return LocalizedStringResource(
                "dashboard.preset.default.description",
                defaultValue: "A balanced dashboard with programme, training, and recovery cards.",
                table: "Shared"
            )
        case .training:
            return LocalizedStringResource(
                "dashboard.preset.training.description",
                defaultValue: "Programme, sessions, timers, and workout-focused cards.",
                table: "Shared"
            )
        case .health:
            return LocalizedStringResource(
                "dashboard.preset.health.description",
                defaultValue: "Recovery, activity, sleep, and nutrition.",
                table: "Shared"
            )
        case .minimal:
            return LocalizedStringResource(
                "dashboard.preset.minimal.description",
                defaultValue: "A simple quick-glance dashboard with your active programme.",
                table: "Shared"
            )
#if DEBUG
        case .mixedCompact:
            return LocalizedStringResource(
                "dashboard.preset.mixedCompact.description",
                defaultValue: "Debug layout test with small cards around one medium card.",
                table: "Shared"
            )
        case .mixedBalanced:
            return LocalizedStringResource(
                "dashboard.preset.mixedBalanced.description",
                defaultValue: "Debug layout test mixing one large, one medium, and several small cards.",
                table: "Shared"
            )
        case .wideStressTest:
            return LocalizedStringResource(
                "dashboard.preset.wideStressTest.description",
                defaultValue: "Debug layout test for 3- and 4-column packing with multiple wide cards.",
                table: "Shared"
            )
#endif
        }
    }
}

struct DashboardModule: Identifiable, Codable {
    var id: String
    var type: ModuleType
    var size: ModuleSize
    var order: Int
    var isVisible: Bool
    
    init(
        id: String = UUID().uuidString,
        type: ModuleType,
        size: ModuleSize = .medium,
        order: Int = 0,
        isVisible: Bool = true
    ) {
        self.id = id
        self.type = type
        self.size = size
        self.order = order
        self.isVisible = isVisible
    }
}
