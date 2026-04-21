import Foundation

enum OnboardingRoutineFocus: String, CaseIterable, Identifiable, Codable {
    case fullBody
    case upper
    case lower
    case push
    case pull
    case legs
    case conditioning
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullBody:
            return "Full Body"
        case .upper:
            return "Upper"
        case .lower:
            return "Lower"
        case .push:
            return "Push"
        case .pull:
            return "Pull"
        case .legs:
            return "Legs"
        case .conditioning:
            return "Conditioning"
        case .custom:
            return "Custom"
        }
    }

    static func defaultDrafts(for dayCount: Int) -> [OnboardingRoutineDayDraft] {
        let resolvedCount = max(2, min(dayCount, 5))
        return (0..<resolvedCount).map { _ in
            OnboardingRoutineDayDraft(focus: .custom)
        }
    }

    static func defaultWeekdays(for dayCount: Int) -> [ProgramWeekday] {
        switch max(2, min(dayCount, 5)) {
        case 2:
            return [.monday, .thursday]
        case 3:
            return [.monday, .wednesday, .friday]
        case 4:
            return [.monday, .tuesday, .thursday, .friday]
        default:
            return [.monday, .tuesday, .wednesday, .thursday, .friday]
        }
    }
}

struct OnboardingRoutineDayDraft: Identifiable, Equatable {
    var id: UUID = UUID()
    var focus: OnboardingRoutineFocus
    var customName: String = ""
    var exerciseIds: [UUID] = []

    var trimmedCustomName: String {
        customName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var preferredName: String {
        if focus == .custom {
            return trimmedCustomName
        }
        return trimmedCustomName.isEmpty ? focus.title : trimmedCustomName
    }

    var scheduleLabel: String {
        preferredName.isEmpty ? "Unnamed Routine" : preferredName
    }
}

struct OnboardingPlanPreview: Equatable {
    let title: String
    let subtitle: String
    let source: OnboardingPlanChoice
    let mode: ProgramMode
    let trainDaysBeforeRest: Int
    let restDays: Int
    let routines: [OnboardingPlanPreviewRoutine]

    var scheduleSummary: String {
        switch mode {
        case .weekly:
            let labels = routines.compactMap { routine -> String? in
                guard let weekdayIndex = routine.weekdayIndex,
                      let weekday = ProgramWeekday(rawValue: weekdayIndex) else {
                    return nil
                }
                return weekday.title
            }
            return labels.isEmpty ? "Weekly schedule" : labels.joined(separator: ", ")
        case .continuous:
            return "\(trainDaysBeforeRest) on / \(restDays) off"
        }
    }
}

struct OnboardingPlanPreviewRoutine: Identifiable, Equatable {
    var id: UUID = UUID()
    let name: String
    let focusLabel: String?
    let weekdayIndex: Int?
    let exerciseIds: [UUID]
    let exercises: [OnboardingPlanPreviewExercise]
}

struct OnboardingPlanPreviewExercise: Identifiable, Equatable {
    let id: UUID
    let name: String
    let detail: String
}

struct OnboardingProgramTemplateBundle: Codable, Equatable {
    let recommendations: [OnboardingProgramTemplate]
}

struct OnboardingProgramTemplate: Codable, Identifiable, Equatable {
    let id: String
    let daysPerWeek: Int
    let title: String
    let subtitle: String
    let programModeRaw: String
    let defaultWeekdays: [Int]
    let trainDaysBeforeRest: Int
    let restDays: Int
    let routines: [OnboardingProgramRoutineTemplate]

    var programMode: ProgramMode {
        ProgramMode(rawValue: programModeRaw) ?? .weekly
    }
}

struct OnboardingProgramRoutineTemplate: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let focus: String
    let slots: [OnboardingProgramSlotTemplate]
}

struct OnboardingProgramSlotTemplate: Codable, Identifiable, Equatable {
    let id: String
    let label: String
    let preferredNpIds: [String]?
    let targetMuscles: [String]
    let keywords: [String]
    let fallbackTypes: [String]
}
