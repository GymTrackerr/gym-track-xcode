import Foundation
import CoreGraphics

enum ModuleSize: String, Codable {
    case small = "1x1"
    case medium = "2x1"
    case large = "2x2"
    
    var displayName: String {
        switch self {
        case .small: return "Small (1x1)"
        case .medium: return "Medium (2x1)"
        case .large: return "Large (2x2)"
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
    
    var displayName: String {
        switch self {
        case .currentWeight: return "Current Weight"
        case .weeklySteps: return "Weekly Steps"
        case .sleep: return "Sleep"
        case .activityRings: return "Activity Rings"
        case .timer: return "Timer"
        case .fitnessWorkouts: return "Fitness Workouts"
        case .truesight: return "TrueSight"
        case .nutrition: return "Nutrition"
        case .sessionVolume: return "Session Volume"
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
        }
        
    }
    
//    var icon: String
}

enum DashboardPreset: String, CaseIterable, Identifiable {
    case `default`
    case training
    case health
    case minimal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default:
            return "Default"
        case .training:
            return "Training"
        case .health:
            return "Health"
        case .minimal:
            return "Minimal"
        }
    }

    var description: String {
        switch self {
        case .default:
            return "The original balanced GymTracker dashboard."
        case .training:
            return "Sessions, timers, and workout-focused cards."
        case .health:
            return "Recovery, activity, sleep, and nutrition."
        case .minimal:
            return "A simple quick-glance dashboard."
        }
    }
}

enum DashboardMoveDirection {
    case left
    case right
    case up
    case down
}

struct DashboardModule: Identifiable, Codable {
    var id: String
    var type: ModuleType
    var size: ModuleSize
    var order: Int
    var isVisible: Bool
    var gridX: Int?
    var gridY: Int?
    var position: CGPoint?
    
    init(
        id: String = UUID().uuidString,
        type: ModuleType,
        size: ModuleSize = .medium,
        order: Int = 0,
        isVisible: Bool = true,
        gridX: Int? = nil,
        gridY: Int? = nil,
        position: CGPoint? = nil
    ) {
        self.id = id
        self.type = type
        self.size = size
        self.order = order
        self.isVisible = isVisible
        self.gridX = gridX
        self.gridY = gridY
        self.position = position
    }
}
