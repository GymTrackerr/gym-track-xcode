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
    @State private var rowMetricsBySessionID: [UUID: SessionRowMetrics] = [:]

    var body: some View {
        VStack(spacing: 12) {
            Picker("Range", selection: $selectedRange) {
                ForEach(SessionTimeRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            summaryCard
                .padding(.horizontal)

            if visibleSessions.isEmpty {
                ContentUnavailableView {
                    Label("No sessions in this period", systemImage: "figure.strengthtraining.traditional")
                } actions: {
                    Button("Add Log") {
                        showingCreateSession = true
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(visibleSessions, id: \.id) { session in
                        NavigationLink {
                            SingleSessionView(session: session)
                                .appBackground()
                        } label: {
                            SessionsPageRowLabel(
                                session: session,
                                metrics: rowMetricsBySessionID[session.id]
                            )
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
                        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                                .padding(.vertical, 6)
                                .padding(.horizontal, 4)
                        )
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Sessions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Import", systemImage: "doc.text") {
                    showingNotesImport = true
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Log", systemImage: "plus") {
                    showingCreateSession = true
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
            .presentationDetents([.medium, .large])
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

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summary.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("\(summary.sessionCount) Session\(summary.sessionCount == 1 ? "" : "s")")
                .font(.headline)

            Text("Total volume: \(sessionService.formattedPounds(summary.totalVolume))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Avg session volume: \(sessionService.formattedPounds(summary.averageSessionVolume))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let averageDurationMinutes = summary.averageDurationMinutes {
                Text("Avg duration: \(Int(averageDurationMinutes.rounded())) min")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func refreshViewData() {
        let interval = selectedRange.dateInterval(referenceDate: Date(), calendar: .current)
        let sessions = sessionService.sessionsInRange(interval)

        var nextRowMetricsBySessionID: [UUID: SessionRowMetrics] = [:]
        var totalVolume: Double = 0
        var totalDurationMinutes = 0
        var sessionsWithDuration = 0

        for session in sessions {
            let sessionVolume = sessionService.sessionVolumeInPounds(session)
            totalVolume += sessionVolume

            let durationMinutes = sessionDurationMinutes(for: session)
            if let durationMinutes {
                totalDurationMinutes += durationMinutes
                sessionsWithDuration += 1
            }

            nextRowMetricsBySessionID[session.id] = SessionRowMetrics(
                exerciseCount: session.sessionEntries.count,
                volumeText: sessionService.formattedPounds(sessionVolume),
                durationText: durationMinutes.map { "\($0) min" }
            )
        }

        visibleSessions = sessions
        rowMetricsBySessionID = nextRowMetricsBySessionID
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

private struct SessionsPageRowLabel: View {
    @Bindable var session: Session
    let metrics: SessionRowMetrics?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(session.timestamp, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                    .font(.headline)

                if let routine = session.routine {
                    Text(routine.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let metrics {
                    Text(metadataText(metrics: metrics))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                }
            }
            .padding(.vertical, 8)
            .padding(.leading, 12)
            .padding(.trailing, 4)

        }
    }

    private func metadataText(metrics: SessionRowMetrics) -> String {
        var components = [
            "\(metrics.exerciseCount) exercise\(metrics.exerciseCount == 1 ? "" : "s")",
            metrics.volumeText
        ]

        if let durationText = metrics.durationText {
            components.append(durationText)
        }

        return components.joined(separator: " · ")
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

private struct SessionRowMetrics {
    let exerciseCount: Int
    let volumeText: String
    let durationText: String?
}
