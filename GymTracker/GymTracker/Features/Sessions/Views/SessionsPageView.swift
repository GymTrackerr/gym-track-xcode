import SwiftUI

struct SessionsPageView: View {
    @EnvironmentObject var sessionService: SessionService
    @EnvironmentObject var splitDayService: RoutineService
    @EnvironmentObject var exerciseService: ExerciseService
    @EnvironmentObject var userService: UserService

    @State private var openedSession: Session?
    @State private var showingNotesImport = false
    @State private var showingCreateSession = false
    @State private var handledOpenCreateSessionRequestID: UUID?

    @State private var selectedRange: SessionTimeRange = .month
    @State private var selectedReferenceDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var visibleSessions: [Session] = []
    @State private var summary = SessionPeriodSummary.empty

    private let openCreateSessionRequestID: UUID?

    init(openCreateSessionRequestID: UUID? = nil) {
        self.openCreateSessionRequestID = openCreateSessionRequestID
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(SessionTimeRange.allCases) { range in
                        FilterPill(
                            title: range.rawValue,
                            isSelected: selectedRange == range
                        )
                        .onTapGesture {
                            selectedRange = range
                            if range != .all {
                                selectedReferenceDate = clampedReferenceDate(for: Date(), range: range)
                            }
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 2)
            }
            .scrollClipDisabled()
            .padding(.vertical, 12)
            .screenContentPadding()

            List {
                summaryRowContent
                    .cardListSummaryContentPadding()
                    .cardListSummaryRowStyle()

                if visibleSessions.isEmpty {
                    EmptyStateView(
                        title: "No sessions in this period",
                        systemImage: "figure.strengthtraining.traditional",
                        message: "Add a session log or choose another period."
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

                    Button {
                        showingCreateSession = true
                    } label: {
                        Label("Add Log", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
                } else {
                    ForEach(visibleSessions, id: \.id) { session in
                        NavigationLink {
                            SingleSessionView(session: session)
                                .appBackground()
                        } label: {
                            SingleSessionLabelView(session: session)
                            .foregroundColor(.primary)
                        }
                        .contextMenu {
                            Button {
                                openedSession = session
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                sessionService.removeSession(session: session)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                sessionService.removeSession(session: session)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .cardListRowStyle()
                    }
                }
            }
            .cardListScreen()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .appBackground()
        .navigationTitle("Sessions")
        .navigationBarTitleDisplayMode(.inline)
        
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    ExerciseHistoryChartView()
                        .appBackground()
                } label: {
                    Image(systemName: "chart.bar.xaxis")
                }
            }
            
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingCreateSession = true
                } label: {
                    Label("New Session", systemImage: "plus.circle").labelStyle(.iconOnly)
                }
                
                Button {
                    showingNotesImport = true
                } label: {
                    Label("Import", systemImage: "doc.text").labelStyle(.iconOnly)
                }
            }
        }
        .onAppear {
            sessionService.loadSessions()
            refreshViewData()
            presentRequestedCreateSessionIfNeeded()
        }
        .onReceive(sessionService.$sessions) { _ in
            refreshViewData()
        }
        .onChange(of: openCreateSessionRequestID) {
            presentRequestedCreateSessionIfNeeded()
        }
        .onChange(of: selectedRange) {
            refreshViewData()
        }
        .onChange(of: selectedReferenceDate) {
            refreshViewData()
        }
        .sheet(isPresented: $showingCreateSession) {
            CreateSessionSheetView(
                openedSession: $openedSession,
                isPresented: $showingCreateSession
            )
            .editorSheetPresentation()
        }
        .navigationDestination(isPresented: $showingNotesImport) {
            NotesImportView(currentUserId: userService.currentUser?.id) {
                sessionService.loadSessions()
                splitDayService.loadSplitDays()
                exerciseService.loadExercises()
                showingNotesImport = false
            }
        }
        .navigationDestination(item: $openedSession) { session in
            SingleSessionView(session: session)
                .appBackground()
        }
    }

    private var summaryRowContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            sessionSummaryHeader

            Text("\(summary.sessionCount) Session\(summary.sessionCount == 1 ? "" : "s")")
                .font(.title3.weight(.semibold))

            HStack(spacing: 10) {
                SummaryMetricTile(
                    title: "Volume",
                    value: SessionService.formattedPounds(summary.totalVolume),
                    systemImage: "scalemass",
                    tint: .purple
                )

                SummaryMetricTile(
                    title: "Avg Vol",
                    value: SessionService.formattedPounds(summary.averageSessionVolume),
                    systemImage: "chart.bar",
                    tint: .green
                )

                if let averageDurationMinutes = summary.averageDurationMinutes {
                    SummaryMetricTile(
                        title: "Avg Time",
                        value: "\(Int(averageDurationMinutes.rounded())) min",
                        systemImage: "clock",
                        tint: .blue
                    )
                } else {
                    SummaryMetricTile(
                        title: "Avg Time",
                        value: "-",
                        systemImage: "clock",
                        tint: .blue
                    )
                }
            }
        }
    }

    private var sessionSummaryHeader: some View {
        HStack(spacing: 10) {
            if selectedRange != .all {
                Button {
                    shiftSelectedPeriod(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(!canShiftSelectedPeriod(by: -1))
            }

            Spacer()

            VStack(alignment: .center, spacing: 3) {
                Text(selectedRange == .all ? "All Sessions" : periodNavigationTitle)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(selectedRange.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if selectedRange != .all {
                Button {
                    shiftSelectedPeriod(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(!canShiftSelectedPeriod(by: 1))
            }
        }
    }

    private var periodNavigationTitle: String {
        let calendar = Calendar.current

        switch selectedRange {
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: selectedReferenceDate) else {
                return selectedReferenceDate.formatted(date: .abbreviated, time: .omitted)
            }
            let end = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            return "\(interval.start.formatted(.dateTime.month(.abbreviated).day())) - \(end.formatted(.dateTime.month(.abbreviated).day()))"
        case .month:
            return selectedReferenceDate.formatted(.dateTime.month(.wide).year())
        case .year:
            return selectedReferenceDate.formatted(.dateTime.year())
        case .all:
            return "All Sessions"
        }
    }

    private func shiftSelectedPeriod(by value: Int) {
        guard canShiftSelectedPeriod(by: value) else { return }
        guard let shiftedDate = shiftedReferenceDate(by: value) else { return }
        selectedReferenceDate = shiftedDate
    }

    private func canShiftSelectedPeriod(by value: Int) -> Bool {
        guard selectedRange != .all, let shiftedDate = shiftedReferenceDate(by: value) else {
            return false
        }

        return isReferenceDateWithinNavigationBounds(shiftedDate, range: selectedRange)
    }

    private func shiftedReferenceDate(by value: Int) -> Date? {
        let calendar = Calendar.current
        let component: Calendar.Component

        switch selectedRange {
        case .week:
            component = .weekOfYear
        case .month:
            component = .month
        case .year:
            component = .year
        case .all:
            return nil
        }

        guard let shiftedDate = calendar.date(byAdding: component, value: value, to: selectedReferenceDate) else {
            return nil
        }

        return calendar.startOfDay(for: shiftedDate)
    }

    private func clampedReferenceDate(for date: Date, range: SessionTimeRange) -> Date {
        let calendar = Calendar.current
        let normalizedDate = calendar.startOfDay(for: date)
        guard range != .all,
              let bounds = navigationBounds(for: range),
              let periodStart = range.periodStart(for: normalizedDate, calendar: calendar) else {
            return normalizedDate
        }

        if periodStart < bounds.minimumAllowedStart {
            return bounds.minimumAllowedStart
        }

        if periodStart > bounds.maximumAllowedStart {
            return bounds.maximumAllowedStart
        }

        return normalizedDate
    }

    private func isReferenceDateWithinNavigationBounds(_ date: Date, range: SessionTimeRange) -> Bool {
        let calendar = Calendar.current
        guard let bounds = navigationBounds(for: range),
              let periodStart = range.periodStart(for: date, calendar: calendar) else {
            return true
        }

        return periodStart >= bounds.minimumAllowedStart && periodStart <= bounds.maximumAllowedStart
    }

    private func navigationBounds(for range: SessionTimeRange) -> PeriodNavigationBounds? {
        guard range != .all else { return nil }

        let calendar = Calendar.current
        let sessions = sessionService.sessionsInRange(nil)
        guard let oldestDate = sessions.map(\.timestamp).min(),
              let oldestPeriodStart = range.periodStart(for: oldestDate, calendar: calendar),
              let currentPeriodStart = range.periodStart(for: Date(), calendar: calendar) else {
            return nil
        }

        let component = range.calendarComponent
        let minimumAllowedStart = calendar.date(byAdding: component, value: -1, to: oldestPeriodStart) ?? oldestPeriodStart
        let maximumAllowedStart = calendar.date(byAdding: component, value: 1, to: currentPeriodStart) ?? currentPeriodStart

        return PeriodNavigationBounds(
            minimumAllowedStart: minimumAllowedStart,
            maximumAllowedStart: maximumAllowedStart
        )
    }

    private func refreshViewData() {
        let interval = selectedRange.dateInterval(referenceDate: selectedReferenceDate, calendar: .current)
        let sessions = sessionService.sessionsInRange(interval)

        var totalVolume: Double = 0
        var totalDurationMinutes = 0
        var sessionsWithDuration = 0

        for session in sessions {
            let sessionVolume = SessionService.sessionVolumeInPounds(session)
            totalVolume += sessionVolume

            let durationMinutes = sessionDurationMinutes(for: session)
            if let durationMinutes {
                totalDurationMinutes += durationMinutes
                sessionsWithDuration += 1
            }
        }

        visibleSessions = sessions
        summary = SessionPeriodSummary(
            title: selectedRange.summaryTitle,
            sessionCount: sessions.count,
            totalVolume: totalVolume,
            averageSessionVolume: sessions.isEmpty ? 0 : totalVolume / Double(sessions.count),
            averageDurationMinutes: sessionsWithDuration == 0
                ? nil
                : Double(totalDurationMinutes) / Double(sessionsWithDuration)
        )
    }

    private func presentRequestedCreateSessionIfNeeded() {
        guard let openCreateSessionRequestID,
              handledOpenCreateSessionRequestID != openCreateSessionRequestID else {
            return
        }

        handledOpenCreateSessionRequestID = openCreateSessionRequestID
        showingCreateSession = true
    }

    private func sessionDurationMinutes(for session: Session) -> Int? {
        guard session.timestampDone > session.timestamp else { return nil }
        let duration = session.timestampDone.timeIntervalSince(session.timestamp)
        guard duration > 0 else { return nil }
        return Int((duration / 60).rounded())
    }
}

private enum SessionTimeRange: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case year = "Year"
    case all = "All"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .week:
            return "Week"
        case .month:
            return "Month"
        case .year:
            return "Year"
        case .all:
            return "All"
        }
    }

    var summaryTitle: String {
        switch self {
        case .week:
            return "This Week"
        case .month:
            return "This Month"
        case .year:
            return "This Year"
        case .all:
            return "All"
        }
    }

    func dateInterval(referenceDate: Date, calendar: Calendar) -> DateInterval? {
        switch self {
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: referenceDate)
        case .month:
            return calendar.dateInterval(of: .month, for: referenceDate)
        case .year:
            return calendar.dateInterval(of: .year, for: referenceDate)
        case .all:
            return nil
        }
    }

    var calendarComponent: Calendar.Component {
        switch self {
        case .week:
            return .weekOfYear
        case .month:
            return .month
        case .year:
            return .year
        case .all:
            return .era
        }
    }

    func periodStart(for date: Date, calendar: Calendar) -> Date? {
        dateInterval(referenceDate: date, calendar: calendar)?.start
    }
}

private struct SessionPeriodSummary {
    let title: String
    let sessionCount: Int
    let totalVolume: Double
    let averageSessionVolume: Double
    let averageDurationMinutes: Double?

    static let empty = SessionPeriodSummary(
        title: SessionTimeRange.month.summaryTitle,
        sessionCount: 0,
        totalVolume: 0,
        averageSessionVolume: 0,
        averageDurationMinutes: nil
    )
}

private struct PeriodNavigationBounds {
    let minimumAllowedStart: Date
    let maximumAllowedStart: Date
}
