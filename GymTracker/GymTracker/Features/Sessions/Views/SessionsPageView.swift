import SwiftUI

struct SessionsPageView: View {
    @EnvironmentObject var sessionService: SessionService
    @EnvironmentObject var splitDayService: RoutineService
    @EnvironmentObject var exerciseService: ExerciseService
    @EnvironmentObject var userService: UserService

    @State private var openedSession: Session?
    @State private var showingNotesImport = false
    @State private var showingCreateSession = false

    @State private var selectedRange: SessionTimeRange = .month
    @State private var visibleSessions: [Session] = []
    @State private var summary = SessionPeriodSummary.empty

    var body: some View {
        List {
            Group {
                Picker("Range", selection: $selectedRange) {
                    ForEach(SessionTimeRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding(10)
            }
            .cardListRowStyle()

            summaryRowContent
                .padding(14)
                .cardListRowStyle()

            if visibleSessions.isEmpty {
                ContentUnavailableView {
                    Label("No sessions in this period", systemImage: "figure.strengthtraining.traditional")
                } actions: {
                    Button("Add Log") {
                        showingCreateSession = true
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
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
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .screenListContentFrame()
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
        }
        .onReceive(sessionService.$sessions) { _ in
            refreshViewData()
        }
        .onChange(of: selectedRange) {
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
        VStack(alignment: .leading, spacing: 6) {
            Text("\(summary.sessionCount) Session\(summary.sessionCount == 1 ? "" : "s")")
                .font(.headline)

            Text("Total volume: \(SessionService.formattedPounds(summary.totalVolume))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Avg session volume: \(SessionService.formattedPounds(summary.averageSessionVolume))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let averageDurationMinutes = summary.averageDurationMinutes {
                Text("Avg duration: \(Int(averageDurationMinutes.rounded())) min")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func refreshViewData() {
        let interval = selectedRange.dateInterval(referenceDate: Date(), calendar: .current)
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
