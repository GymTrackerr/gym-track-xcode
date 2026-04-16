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
        switch self {
        case .months3:
            return "3 months"
        case .months6:
            return "6 months"
        case .months12:
            return "12 months"
        case .months24:
            return "24 months"
        case .all:
            return "All"
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
