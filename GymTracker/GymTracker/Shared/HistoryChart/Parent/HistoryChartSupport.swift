import Foundation

enum HistoryChartTimeframe: String, CaseIterable, Identifiable {
    case week = "W"
    case month = "M"
    case sixMonths = "6M"
    case year = "Y"
    case fiveYears = "5Y"

    var id: String { rawValue }

    var barsPerWindow: Int {
        switch self {
        case .week: 7
        case .month: 31
        case .sixMonths: 26
        case .year: 12
        case .fiveYears: 5
        }
    }

    var barFillRatio: CGFloat { 0.8 }

    /// Calendar component for each bar's time bucket (day, week, month, year)
    var bucketCalendarComponent: Calendar.Component {
        switch self {
        case .week, .month: .day
        case .sixMonths: .weekOfYear
        case .year: .month
        case .fiveYears: .year
        }
    }

    /// Calendar component that defines the visible window boundary (for shifting & snapping)
    var windowCalendarComponent: Calendar.Component {
        switch self {
        case .week: .weekOfYear
        case .month, .sixMonths: .month
        case .year, .fiveYears: .year
        }
    }

    /// How many window-component units to shift when navigating forward/back
    var shiftMultiplier: Int {
        switch self {
        case .sixMonths: 6
        case .fiveYears: 5
        default: 1
        }
    }

    /// Approximate visible domain length in days
    var visibleDomainDays: Int {
        switch self {
        case .week: 7
        case .month: 31
        case .sixMonths: 183
        case .year: 366
        case .fiveYears: 1830
        }
    }

    /// Calendar component used for axis marks, nil means automatic
    var axisMarkCalendarComponent: Calendar.Component? {
        switch self {
        case .week, .month: nil
        case .sixMonths, .year: .month
        case .fiveYears: .year
        }
    }
}

enum HistoryChartRenderStyle: String, CaseIterable, Identifiable {
    case bar
    case line
    case barLine

    var id: String { rawValue }
}

struct HistoryChartPoint: Identifiable {
    let startDate: Date
    let endDate: Date
    let value: Double
    let segments: [HistoryChartBarSegment]
    let summaryAverageNumerator: Double?
    let summaryAverageDenominator: Double?

    init(
        startDate: Date,
        endDate: Date,
        value: Double,
        segments: [HistoryChartBarSegment] = [],
        summaryAverageNumerator: Double? = nil,
        summaryAverageDenominator: Double? = nil
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.value = value
        self.segments = segments
        self.summaryAverageNumerator = summaryAverageNumerator
        self.summaryAverageDenominator = summaryAverageDenominator
    }

    var id: TimeInterval {
        startDate.timeIntervalSinceReferenceDate + (endDate.timeIntervalSinceReferenceDate * 0.0001)
    }

    var date: Date {
        startDate.addingTimeInterval(endDate.timeIntervalSince(startDate) / 2)
    }

    var plottedValue: Double {
        guard !segments.isEmpty else { return value }
        return segments.reduce(0.0) { $0 + $1.value }
    }

    var effectiveSummaryAverageNumerator: Double {
        summaryAverageNumerator ?? plottedValue
    }

    var effectiveSummaryAverageDenominator: Double {
        summaryAverageDenominator ?? 1
    }

    func segmentValue(for key: String) -> Double? {
        segments.first(where: { $0.key == key })?.value
    }
}

enum HistoryChartSegmentStyle: String, Codable {
    case primary
    case secondary
    case tertiary
    case positive
    case warning
    case negative
    case negativeSecondary
    case neutral
}

struct HistoryChartBarSegment: Identifiable, Hashable {
    let key: String
    let value: Double
    let style: HistoryChartSegmentStyle
    let label: String?

    init(
        key: String,
        value: Double,
        style: HistoryChartSegmentStyle,
        label: String? = nil
    ) {
        self.key = key
        self.value = value
        self.style = style
        self.label = label
    }

    var id: String { key }
}

typealias HistoryChartLoadIntervalProvider = (DateInterval, HistoryChartTimeframe) -> DateInterval

enum HistoryChartLoadSupport {
    static func bufferedInterval(
        for visibleInterval: DateInterval,
        timeframe: HistoryChartTimeframe,
        calendar: Calendar = .current
    ) -> DateInterval {
        guard visibleInterval.end > visibleInterval.start else {
            return visibleInterval
        }

        let step = timeframe.shiftMultiplier
        let component = timeframe.windowCalendarComponent
        let startWindowStart = calendar.dateInterval(of: component, for: visibleInterval.start)?.start ?? visibleInterval.start
        let endAnchor = visibleInterval.end.addingTimeInterval(-1)
        let endWindowStart = calendar.dateInterval(of: component, for: endAnchor)?.start ?? endAnchor
        let endWindowEnd = calendar.date(byAdding: component, value: step, to: endWindowStart) ?? visibleInterval.end

        let bufferedStart = calendar.date(byAdding: component, value: -step, to: startWindowStart) ?? startWindowStart
        let bufferedEnd = calendar.date(byAdding: component, value: step, to: endWindowEnd) ?? endWindowEnd

        return DateInterval(start: bufferedStart, end: bufferedEnd)
    }
}

enum HistoryChartCalculator {
    static func sanitizeBounds(
        oldest: Date?,
        newest: Date?,
        calendar: Calendar = .current,
        now: Date = Date(),
        minimumYear: Int = 2010
    ) -> (oldest: Date?, newest: Date?) {
        guard let oldest, let newest else {
            return (nil, nil)
        }

        guard oldest <= newest else {
            return (nil, nil)
        }

        let minAllowed = calendar.date(from: DateComponents(year: minimumYear, month: 1, day: 1)) ?? oldest
        let maxAllowed = calendar.date(byAdding: .day, value: 1, to: now) ?? now

        let clampedOldest = max(oldest, minAllowed)
        let clampedNewest = min(newest, maxAllowed)
        guard clampedNewest >= clampedOldest else {
            return (nil, nil)
        }

        return (clampedOldest, clampedNewest)
    }

    static func currentWindow(
        for timeframe: HistoryChartTimeframe,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DateInterval {
        switch timeframe {
        case .week:
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
            let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? weekStart.addingTimeInterval(7 * 24 * 3600)
            return DateInterval(start: weekStart, end: weekEnd)

        case .month:
            let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
            return DateInterval(start: monthStart, end: monthEnd)

        case .sixMonths:
            let currentMonthStart = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .month, value: -2, to: currentMonthStart) ?? currentMonthStart
            let end = calendar.date(byAdding: .month, value: 4, to: currentMonthStart) ?? currentMonthStart
            return DateInterval(start: start, end: end)

        case .year:
            let yearStart = calendar.dateInterval(of: .year, for: now)?.start ?? calendar.startOfDay(for: now)
            let yearEnd = calendar.date(byAdding: .year, value: 1, to: yearStart) ?? yearStart
            return DateInterval(start: yearStart, end: yearEnd)

        case .fiveYears:
            let yearStart = calendar.dateInterval(of: .year, for: now)?.start ?? calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .year, value: -3, to: yearStart) ?? yearStart
            let end = calendar.date(byAdding: .year, value: 2, to: yearStart) ?? yearStart
            return DateInterval(start: start, end: end)
        }
    }

    static func shift(
        anchorDate: Date,
        timeframe: HistoryChartTimeframe,
        direction: Int,
        calendar: Calendar = .current
    ) -> Date {
        calendar.date(byAdding: timeframe.windowCalendarComponent, value: timeframe.shiftMultiplier * direction, to: anchorDate) ?? anchorDate
    }

    static func visibleDomainLength(for timeframe: HistoryChartTimeframe) -> TimeInterval {
        Double(timeframe.visibleDomainDays) * 24 * 60 * 60
    }

    static func xAxisLabel(
        for date: Date,
        timeframe: HistoryChartTimeframe,
        calendar: Calendar = .current
    ) -> String {
        switch timeframe {
        case .week:
            return date.formatted(.dateTime.weekday(.abbreviated))
        case .month:
            return String(calendar.component(.day, from: date))
        case .sixMonths:
            return date.formatted(.dateTime.month(.abbreviated))
        case .year:
            return String(date.formatted(.dateTime.month(.abbreviated)).prefix(1))
        case .fiveYears:
            return date.formatted(.dateTime.year())
        }
    }

    static func selectionLabel(
        for point: HistoryChartPoint,
        timeframe: HistoryChartTimeframe,
        calendar: Calendar = .current
    ) -> String {
        switch timeframe {
        case .week, .month:
            return point.startDate.formatted(.dateTime.month(.abbreviated).day().year())
        case .sixMonths:
            let start = point.startDate
            let end = calendar.date(byAdding: .day, value: -1, to: point.endDate) ?? point.endDate
            let startMonth = calendar.component(.month, from: start)
            let endMonth = calendar.component(.month, from: end)
            let startMonthText = start.formatted(.dateTime.month(.abbreviated))
            let endMonthText = end.formatted(.dateTime.month(.abbreviated))
            let startDay = calendar.component(.day, from: start)
            let endDay = calendar.component(.day, from: end)
            let yearText = end.formatted(.dateTime.year())

            if startMonth == endMonth {
                return "\(startMonthText) \(startDay)-\(endDay), \(yearText)"
            }
            return "\(startMonthText) \(startDay) - \(endMonthText) \(endDay), \(yearText)"
        case .year:
            return point.startDate.formatted(.dateTime.month(.wide).year())
        case .fiveYears:
            return point.startDate.formatted(.dateTime.year())
        }
    }

    static func axisMarkDates(
        for timeframe: HistoryChartTimeframe,
        interval: DateInterval,
        calendar: Calendar = .current
    ) -> [Date]? {
        guard let component = timeframe.axisMarkCalendarComponent else { return nil }
        var marks: [Date] = []
        var cursor = calendar.dateInterval(of: component, for: interval.start)?.start ?? interval.start
        while cursor < interval.end {
            marks.append(cursor)
            cursor = calendar.date(byAdding: component, value: 1, to: cursor) ?? interval.end
        }
        return marks
    }

    static func bucketIntervals(
        interval: DateInterval,
        timeframe: HistoryChartTimeframe,
        calendar: Calendar = .current
    ) -> [DateInterval] {
        var buckets: [DateInterval] = []
        var cursor = bucketStart(for: interval.start, timeframe: timeframe, calendar: calendar)

        while cursor < interval.end {
            let next = nextBucketStart(after: cursor, timeframe: timeframe, calendar: calendar)
            buckets.append(DateInterval(start: cursor, end: next))
            cursor = next
        }

        return buckets
    }

    private static func bucketStart(
        for date: Date,
        timeframe: HistoryChartTimeframe,
        calendar: Calendar
    ) -> Date {
        calendar.dateInterval(of: timeframe.bucketCalendarComponent, for: date)?.start ?? date
    }

    private static func nextBucketStart(
        after date: Date,
        timeframe: HistoryChartTimeframe,
        calendar: Calendar
    ) -> Date {
        calendar.date(byAdding: timeframe.bucketCalendarComponent, value: 1, to: date) ?? date
    }
}
