import Foundation

enum HealthHistorySyncRange: String, CaseIterable, Identifiable {
    case months3
    case months6
    case months12
    case months24
    case all

    static let defaultSelection: HealthHistorySyncRange = .months12

    var id: String { rawValue }

    var title: String {
        String(localized: titleResource)
    }

    var titleResource: LocalizedStringResource {
        switch self {
        case .months3:
            return LocalizedStringResource("settings.healthHistoryRange.months3", defaultValue: "3 months", table: "Settings")
        case .months6:
            return LocalizedStringResource("settings.healthHistoryRange.months6", defaultValue: "6 months", table: "Settings")
        case .months12:
            return LocalizedStringResource("settings.healthHistoryRange.months12", defaultValue: "12 months", table: "Settings")
        case .months24:
            return LocalizedStringResource("settings.healthHistoryRange.months24", defaultValue: "24 months", table: "Settings")
        case .all:
            return LocalizedStringResource("settings.healthHistoryRange.all", defaultValue: "All", table: "Settings")
        }
    }

    func startDay(endingOn endDay: Date, calendar: Calendar = .current, maxYearsBackForAll: Int = 25) -> Date {
        let normalizedEndDay = calendar.startOfDay(for: endDay)
        switch self {
        case .months3:
            return calendar.date(byAdding: .month, value: -3, to: normalizedEndDay) ?? normalizedEndDay
        case .months6:
            return calendar.date(byAdding: .month, value: -6, to: normalizedEndDay) ?? normalizedEndDay
        case .months12:
            return calendar.date(byAdding: .month, value: -12, to: normalizedEndDay) ?? normalizedEndDay
        case .months24:
            return calendar.date(byAdding: .month, value: -24, to: normalizedEndDay) ?? normalizedEndDay
        case .all:
            return calendar.date(byAdding: .year, value: -maxYearsBackForAll, to: normalizedEndDay) ?? normalizedEndDay
        }
    }
}
