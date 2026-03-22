import Foundation

struct HealthKitDateNormalizer {
    private let calendar: Calendar

    init(calendar: Calendar = HealthKitDateNormalizer.defaultCalendar()) {
        self.calendar = calendar
    }

    private static func defaultCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    func dayKey(_ date: Date) -> String {
        let day = startOfDay(date)
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
    }

    func buildDateRange(endingOn endDate: Date, days: Int) -> [Date] {
        let clampedDays = max(days, 1)
        let endDayStart = startOfDay(endDate)
        let startDay = calendar.date(byAdding: .day, value: -(clampedDays - 1), to: endDayStart) ?? endDayStart
        return (0..<clampedDays).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: startDay)
        }
    }

    func sameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        startOfDay(lhs) == startOfDay(rhs)
    }
}
