import Foundation
import SwiftUI

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
}

enum ModuleType: String, Codable, CaseIterable {
    case currentWeight = "currentWeight"
    case weeklySteps = "weeklySteps"
    case sleep = "sleep"
    case activityRings = "activityRings"
    case timer = "timer"
    case fitnessWorkouts = "fitnessWorkouts"
    case fitsight = "fitsight"
    case nutrition = "nutrition"
    
    var displayName: String {
        switch self {
        case .currentWeight: return "Current Weight"
        case .weeklySteps: return "Weekly Steps"
        case .sleep: return "Sleep"
        case .activityRings: return "Activity Rings"
        case .timer: return "Timer"
        case .fitnessWorkouts: return "Fitness Workouts"
        case .fitsight: return "FitSight"
        case .nutrition: return "Nutrition"
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
        case .fitsight: return "video"
        case .nutrition: return "fork.knife"
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
        case .fitsight:
            return [.small]
        case .nutrition:
            return [.small]
        }
        
    }
    
//    var icon: String
}

struct DashboardModule: Identifiable, Codable {
    var id: String
    var type: ModuleType
    var size: ModuleSize
    var order: Int
    var isVisible: Bool
    var position: CGPoint?
    
    init(
        id: String = UUID().uuidString,
        type: ModuleType,
        size: ModuleSize = .medium,
        order: Int = 0,
        isVisible: Bool = true,
        position: CGPoint? = nil
    ) {
        self.id = id
        self.type = type
        self.size = size
        self.order = order
        self.isVisible = isVisible
        self.position = position
    }
}
