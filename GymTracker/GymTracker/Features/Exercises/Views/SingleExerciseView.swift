//
//  SingleExerciseView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftUI
import Charts
import WebKit

enum ProgressRange: String, CaseIterable, Identifiable {
    case days = "Days"
    case weeks = "Weeks"
    case months = "Months"
    case years = "Years"

    var id: String { rawValue }
}

enum ProgressMetric: String, CaseIterable, Identifiable {
    case maxWeight
    case averageWeight
    case totalVolume
    case totalReps
    case averageReps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .maxWeight:
            return "Max Weight"
        case .averageWeight:
            return "Average Weight"
        case .totalVolume:
            return "Total Volume"
        case .totalReps:
            return "Total Reps"
        case .averageReps:
            return "Average Reps"
        }
    }
}

enum CardioProgressMetric: String, CaseIterable, Identifiable {
    case totalDistance
    case totalDuration
    case averagePace
    case bestPace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .totalDistance:
            return "Total Distance"
        case .totalDuration:
            return "Total Duration"
        case .averagePace:
            return "Avg Pace"
        case .bestPace:
            return "Best Pace"
        }
    }
}

fileprivate struct ExerciseDetailSnapshot {
    let id: UUID
    let npId: String?
    let name: String
    let aliases: [String]
    let type: ExerciseType
    let isUserCreated: Bool
    let isArchived: Bool
    let equipment: String?
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let instructions: [String]
    let images: [String]
    let cardio: Bool
    let setDisplayKind: SetDisplayExerciseKind

    init(exercise: Exercise) {
        id = exercise.id
        npId = exercise.npId
        name = exercise.name
        aliases = exercise.aliases ?? []
        type = exercise.exerciseType
        isUserCreated = exercise.isUserCreated
        isArchived = exercise.isArchived
        equipment = exercise.equipment
        primaryMuscles = exercise.primary_muscles ?? []
        secondaryMuscles = exercise.secondary_muscles ?? []
        instructions = exercise.instructions ?? []
        images = exercise.images ?? []
        cardio = exercise.cardio
        setDisplayKind = exercise.setDisplayKind
    }
}

struct SingleExerciseView: View {
    private let exerciseId: UUID
    @EnvironmentObject var exerciseService: ExerciseService
    @State private var detailSnapshot: ExerciseDetailSnapshot?

    init(exercise: Exercise) {
        self.exerciseId = exercise.id
        _detailSnapshot = State(initialValue: ExerciseDetailSnapshot(exercise: exercise))
    }

    init(exerciseId: UUID) {
        self.exerciseId = exerciseId
        _detailSnapshot = State(initialValue: nil)
    }

    private var liveExercise: Exercise? {
        exerciseService.exercises.first(where: { $0.id == exerciseId }) ??
        exerciseService.archivedExercises.first(where: { $0.id == exerciseId })
    }
    
    var body: some View {
        Group {
            if let detailSnapshot {
                ExerciseDetailView(
                    exerciseId: exerciseId,
                    initialSnapshot: detailSnapshot
                )
                    .navigationTitle(detailSnapshot.name)
                    .toolbar {
                        if detailSnapshot.isArchived, let liveExercise {
                            Button("Restore") {
                                do {
                                    try exerciseService.restore(liveExercise)
                                } catch {
                                    print("Failed to restore exercise: \(error)")
                                }
                            }
                        }
                    }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)

                    Text("Exercise Unavailable")
                        .font(.headline)

                    Text("This exercise changed during sync. Go back and reopen it from the refreshed list.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
        .onAppear {
            refreshSnapshotIfNeeded()
        }
        .onChange(of: exerciseService.exerciseListRevision) { _, _ in
            refreshSnapshotIfNeeded()
        }
    }

    private func refreshSnapshotIfNeeded() {
        guard let liveExercise else { return }
        detailSnapshot = ExerciseDetailSnapshot(exercise: liveExercise)
    }
}

private struct ExerciseDetailView: View {
    fileprivate struct LoggedExerciseSessionTarget: Identifiable, Hashable {
        let session: Session
        let navigationContext: SessionNavigationContext

        var id: UUID { session.id }

        static func == (lhs: LoggedExerciseSessionTarget, rhs: LoggedExerciseSessionTarget) -> Bool {
            lhs.session.id == rhs.session.id && lhs.navigationContext == rhs.navigationContext
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(session.id)
            hasher.combine(navigationContext)
        }
    }

    private let exerciseId: UUID
    @EnvironmentObject var exerciseService: ExerciseService
    @EnvironmentObject var sessionService: SessionService
    @EnvironmentObject var seService: SessionExerciseService
    @EnvironmentObject var progressionService: ProgressionService

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter
    }()

    private static let yearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("yyyy")
        return formatter
    }()

    private struct RepSample {
        let date: Date
        let weight: Double
        let unit: WeightUnit
        let reps: Int
    }

    private struct ProgressPoint: Identifiable {
        let date: Date
        let value: Double
        var id: TimeInterval { date.timeIntervalSinceReferenceDate }
    }

    private struct PreviousSessionItem: Identifiable {
        let sessionId: UUID
        let timestamp: Date
        let subtitle: String

        var id: UUID { sessionId }
    }

    @State private var showHowToPerform = true
    @State private var showExerciseData = true
    @State private var showProgress = true
    @State private var selectedTab: ProgressMetric = .totalVolume
    @State private var selectedCardioTab: CardioProgressMetric = .totalDistance
    @State private var selectedRange: ProgressRange = .months
    @State private var selectedDisplayUnit: WeightUnit? = nil
    @State private var selectedDistanceUnit: DistanceUnit = .km
    @State private var showingLogExerciseSheet = false
    @State private var showingAddRoutineSheet = false
    @State private var showingTransferExerciseSheet = false
    @State private var showingProgressionSheet = false
    @State private var exerciseAliasDraft = ""
    @State private var isEditingAliases = false
    @State private var aliasError: String? = nil
    @State private var exerciseSnapshot: ExerciseDetailSnapshot
    @State private var matchingEntriesCache: [SessionEntry] = []
    @State private var cardioSetsCache: [SessionSet] = []
    @State private var repSamplesCache: [RepSample] = []
    @State private var previousSessionsCache: [PreviousSessionItem] = []
    @State private var chartPointsCache: [ProgressPoint] = []
    @State private var openedSessionTarget: LoggedExerciseSessionTarget?
    private let previousLogsSectionID = "previous-logs-section"

    init(exerciseId: UUID, initialSnapshot: ExerciseDetailSnapshot) {
        self.exerciseId = exerciseId
        _exerciseSnapshot = State(initialValue: initialSnapshot)
    }

    private var liveExercise: Exercise? {
        exerciseService.exercises.first(where: { $0.id == exerciseId }) ??
        exerciseService.archivedExercises.first(where: { $0.id == exerciseId })
    }

    private var progressionExercise: ProgressionExercise? {
        progressionService.exerciseOverride(for: exerciseId)
    }

    private var inheritedProgressionExercise: ProgressionExercise? {
        guard let progressionExercise = progressionService.progressionExercise(for: exerciseId),
              !progressionExercise.isExplicitOverride else {
            return nil
        }
        return progressionExercise
    }

    private var progressionProfile: ProgressionProfile? {
        guard let progressionExercise else { return nil }
        return progressionService.profile(for: progressionExercise)
    }

    private var inheritedProgressionProfile: ProgressionProfile? {
        guard let inheritedProgressionExercise else { return nil }
        return progressionService.profile(for: inheritedProgressionExercise)
    }


    var body: some View {
        ScrollViewReader { proxy in
            exerciseContent(proxy: proxy)
        }
        .modifier(ExerciseDetailNavigationModifier(
            openedSessionTarget: $openedSessionTarget,
            showingLogExerciseSheet: $showingLogExerciseSheet,
            showingAddRoutineSheet: $showingAddRoutineSheet,
            showingTransferExerciseSheet: $showingTransferExerciseSheet,
            showingProgressionSheet: $showingProgressionSheet,
            liveExercise: liveExercise,
            exerciseId: exerciseId,
            onOpenSession: handleOpenedSession
        ))
        .onAppear {
            sessionService.loadSessions()
            progressionService.ensureBuiltInProfiles()
            progressionService.loadProfiles()
            progressionService.loadProgressionExercises()
            refreshDerivedData()
            if selectedDisplayUnit == nil {
                selectedDisplayUnit = dominantUnit
            }
            exerciseAliasDraft = ""
            isEditingAliases = false
        }
        .onChange(of: exerciseService.exerciseListRevision) { _, _ in
            refreshSnapshotIfNeeded()
            refreshDerivedData()
        }
        .onReceive(sessionService.$sessions) { _ in
            refreshDerivedData()
        }
        .onReceive(progressionService.$progressionExercises) { _ in
            refreshSnapshotIfNeeded()
        }
        .onChange(of: selectedTab) { _, _ in
            refreshDerivedData()
        }
        .onChange(of: selectedCardioTab) { _, _ in
            refreshDerivedData()
        }
        .onChange(of: selectedRange) { _, _ in
            refreshDerivedData()
        }
        .onChange(of: selectedDisplayUnit) { _, _ in
            refreshDerivedData()
        }
        .onChange(of: selectedDistanceUnit) { _, _ in
            refreshDerivedData()
        }
    }

    @ViewBuilder
    private func exerciseContent(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroMediaSection
                exerciseInfoSection
                instructionsSection
                progressionSection
                progressSection
                logExerciseButton
                addToRoutineButton
                trueSightButton
                previousLogsSection
                transferHistoryButton
            }
            .screenContentPadding()
        }
        .toolbar {
            detailToolbar(proxy: proxy)
        }
        .background(detailBackground)
        .navigationTitle(exerciseSnapshot.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var heroMediaSection: some View {
        if let gifURL = exerciseService.gifURL(
            images: exerciseSnapshot.images,
            isUserCreated: exerciseSnapshot.isUserCreated
        ) {
            CachedMediaView(url: gifURL)
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var exerciseInfoSection: some View {
        if hasExerciseInfo {
            DisclosureGroup(isExpanded: $showExerciseData) {
                VStack(alignment: .leading, spacing: 12) {
                    detailRow("Exercise Type", exerciseSnapshot.type.name)

                    if let equipment = cleanedString(exerciseSnapshot.equipment) {
                        detailRow("Equipment", equipment)
                    }

                    if exerciseSnapshot.cardio {
                        detailRow("Cardio", "Yes")
                        if let totalDistance = cardioTotalDistanceLabel {
                            detailRow("Total Distance", totalDistance)
                        }
                        if let totalDuration = cardioTotalDurationLabel {
                            detailRow("Total Duration", totalDuration)
                        }
                        if let avgPace = cardioAveragePaceLabel {
                            detailRow("Avg Pace", avgPace)
                        }
                    }

                    if !aliases.isEmpty || isEditingAliases {
                        aliasSection
                    }

                    if !primaryMuscles.isEmpty {
                        muscleSection(title: "Primary Muscles", muscles: primaryMuscles)
                    }

                    if !secondaryMuscles.isEmpty {
                        muscleSection(title: "Secondary Muscles", muscles: secondaryMuscles)
                    }
                }
                .padding(.top, 4)
            } label: {
                Text("Exercise Data")
                    .font(.headline)
            }
            .padding()
            .adaptiveCardSurface(cornerRadius: 12)
        }
    }

    @ViewBuilder
    private var aliasSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Aliases")
                .font(.subheadline)
                .fontWeight(.semibold)
                .accessibilityLabel("Exercise Aliases")

            if isEditingAliases {
                aliasInputField
                if !aliases.isEmpty {
                    aliasEditList
                }
                if let error = aliasError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            } else {
                aliasViewList
            }
        }
    }

    private func muscleSection(title: String, muscles: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(muscles, id: \.self) { muscle in
                        MuscleChip(text: muscle)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private var instructionsSection: some View {
        if !instructions.isEmpty {
            DisclosureGroup(isExpanded: $showHowToPerform) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(instructions.enumerated()), id: \.offset) { i, step in
                        Text("\(i + 1). \(step)")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 4)
            } label: {
                Text("How to Perform")
                    .font(.headline)
            }
            .padding()
            .adaptiveCardSurface(cornerRadius: 12)
        }
    }

    private var progressionSection: some View {
        ExerciseProgressionCardView(
            progressionExercise: progressionExercise,
            profile: progressionProfile,
            inheritedProgressionExercise: inheritedProgressionExercise,
            inheritedProfile: inheritedProgressionProfile,
            onEdit: {
                showingProgressionSheet = true
            }
        )
    }

    private var progressSection: some View {
        DisclosureGroup(isExpanded: $showProgress) {
            VStack(alignment: .leading, spacing: 10) {
                progressMetricSelector
                progressRangeSelector
                progressUnitSelector
                progressChart
                openFullChartButton
            }
            .padding(.top, 6)
        } label: {
            Text("Your Progress")
                .font(.headline)
                .foregroundStyle(.tint)
        }
        .padding()
        .adaptiveCardSurface(cornerRadius: 12)
    }

    private var progressMetricSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if hasCardioProgress {
                    ForEach(CardioProgressMetric.allCases) { tab in
                        metricButton(
                            title: tab.title,
                            isSelected: selectedCardioTab == tab,
                            action: { selectedCardioTab = tab }
                        )
                    }
                } else {
                    ForEach(ProgressMetric.allCases) { tab in
                        metricButton(
                            title: tab.title,
                            isSelected: selectedTab == tab,
                            action: { selectedTab = tab }
                        )
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .overlay(horizontalScrollHints)
    }

    private var progressRangeSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ProgressRange.allCases) { range in
                    metricButton(
                        title: range.rawValue,
                        isSelected: selectedRange == range,
                        action: { selectedRange = range }
                    )
                }
            }
            .padding(.vertical, 2)
        }
        .overlay(horizontalScrollHints)
    }

    private var progressUnitSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if hasCardioProgress {
                    ForEach([DistanceUnit.km, DistanceUnit.mi], id: \.rawValue) { unit in
                        metricButton(
                            title: unit.rawValue.uppercased(),
                            isSelected: selectedDistanceUnit == unit,
                            action: { selectedDistanceUnit = unit }
                        )
                    }
                } else {
                    ForEach(WeightUnit.allCases) { unit in
                        metricButton(
                            title: unit.name + "s",
                            isSelected: displayUnit == unit,
                            action: { selectedDisplayUnit = unit }
                        )
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .overlay(horizontalScrollHints)
    }

    private func metricButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(isSelected ? Color.green.opacity(0.2) : Color.gray.opacity(0.1))
                .cornerRadius(8)
                .foregroundColor(isSelected ? .green : .primary)
        }
    }

    private var progressChart: some View {
        Chart(chartPoints) { point in
            LineMark(
                x: .value("Date", point.date, unit: chartXAxisStride),
                y: .value("Value", point.value)
            )
            .symbol(.circle)
            .interpolationMethod(.catmullRom)
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: chartXAxisStride)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(chartXAxisLabel(date))
                    }
                }
            }
        }
        .chartYScale(domain: 0...chartYMax)
        .frame(height: 160)
    }

    private var openFullChartButton: some View {
        NavigationLink {
            if let liveExercise {
                ExerciseHistoryChartView(exercise: liveExercise)
                    .appBackground()
            }
        } label: {
            Label("Open Full Chart", systemImage: "chart.bar.xaxis")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .disabled(liveExercise == nil)
    }

    private var logExerciseButton: some View {
        Button {
            showingLogExerciseSheet = true
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Log this Exercise")
                    .fontWeight(.semibold)
            }
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor)
            .cornerRadius(14)
        }
        .padding(.bottom, 10)
    }

    private var addToRoutineButton: some View {
        Button {
            showingAddRoutineSheet = true
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Add to Routine")
                    .fontWeight(.semibold)
            }
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor)
            .cornerRadius(14)
        }
        .padding(.bottom, 12)
    }

    private var trueSightButton: some View {
        NavigationLink {
            TrueSightView(initialExerciseId: exerciseId)
                .appBackground()
        } label: {
            HStack {
                Image(systemName: "video.badge.waveform")
                Text("Open in TrueSight")
                    .fontWeight(.semibold)
            }
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity)
            .padding()
            .background(canOpenTrueSight ? Color.accentColor : Color.gray.opacity(0.3))
            .cornerRadius(14)
        }
        .padding(.bottom, 12)
        .disabled(!canOpenTrueSight)
    }

    private var canOpenTrueSight: Bool {
        exerciseSnapshot.npId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var previousLogsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Previous Logs")
                .font(.headline)
                .id(previousLogsSectionID)

            if previousSessions.isEmpty {
                EmptyStateView(
                    title: "No Previous Logs",
                    systemImage: "clock.arrow.circlepath",
                message: "Completed sessions for this exercise will appear here."
            )
            } else {
                VStack(spacing: 8) {
                    ForEach(previousSessions) { item in
                        previousLogLink(for: item)
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }

    private func previousLogLink(for item: PreviousSessionItem) -> some View {
        NavigationLink {
            if let session = session(for: item.sessionId) {
                SingleSessionView(
                    session: session,
                    navigationContext: .fromExerciseHistory(
                        sessionId: session.id,
                        exerciseId: exerciseId
                    )
                )
                .appBackground()
            }
        } label: {
            CardRowContainer {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.timestamp.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var transferHistoryButton: some View {
        Button {
            showingTransferExerciseSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.arrow.right")
                Text("Transfer History")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.gray.opacity(0.14))
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, 14)
    }

    private var detailBackground: some View {
        AppBackgroundView()
    }

    @ToolbarContentBuilder
    private func detailToolbar(proxy: ScrollViewProxy) -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            NavigationLink {
                if let liveExercise {
                    ExerciseHistoryChartView(exercise: liveExercise)
                        .appBackground()
                }
            } label: {
                Label("Charts", systemImage: "chart.bar.xaxis")
            }
            .disabled(liveExercise == nil)
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                isEditingAliases.toggle()
            } label: {
                Label(isEditingAliases ? "Done Editing" : "Edit", systemImage: isEditingAliases ? "checkmark.circle" : "pencil")
            }
            .disabled(exerciseSnapshot.isArchived)

            Button {
                withAnimation(.easeInOut) {
                    proxy.scrollTo(previousLogsSectionID, anchor: .top)
                }
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
        }
    }

    private func handleOpenedSession(_ session: Session, navigationContext: SessionNavigationContext) {
        openedSessionTarget = LoggedExerciseSessionTarget(
            session: session,
            navigationContext: navigationContext
        )
    }

    private var matchingEntries: [SessionEntry] {
        matchingEntriesCache
    }

    private var primaryMuscles: [String] {
        normalizedList(exerciseSnapshot.primaryMuscles)
    }

    private var secondaryMuscles: [String] {
        normalizedList(exerciseSnapshot.secondaryMuscles)
    }

    private var aliases: [String] {
        normalizedList(exerciseSnapshot.aliases)
    }
    
    private var aliasInputField: some View {
        HStack(spacing: 8) {
            TextField("Add alias", text: $exerciseAliasDraft)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Alias input")
                .accessibilityHint("Enter a new alias for this exercise")
            
            Button("Add") {
                addExerciseAlias()
            }
            .buttonStyle(.bordered)
            .disabled(exerciseAliasDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Add alias")
        }
    }
    
    private var aliasEditList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(aliases.indices, id: \.self) { index in
                    HStack(spacing: 4) {
                        Text(aliases[index])
                            .font(.caption)
                            .lineLimit(1)
                        
                        Button {
                            removeExerciseAlias(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(aliases[index])")
                        .accessibilityHint("Removes this alias from the exercise")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
                }
            }
            .padding(.vertical, 2)
        }
    }
    
    private var aliasViewList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(aliases.indices, id: \.self) { index in
                    MuscleChip(text: aliases[index])
                        .accessibilityLabel("Alias: \(aliases[index])")
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var instructions: [String] {
        normalizedList(exerciseSnapshot.instructions)
    }

    private var hasExerciseInfo: Bool {
        cleanedString(exerciseSnapshot.equipment) != nil ||
        !aliases.isEmpty ||
        !primaryMuscles.isEmpty ||
        !secondaryMuscles.isEmpty ||
        !cardioSets.isEmpty
    }

    private var cardioSets: [SessionSet] {
        cardioSetsCache
    }

    private var hasCardioProgress: Bool {
        exerciseSnapshot.cardio && !cardioSets.isEmpty
    }

    private var cardioTotalDistanceLabel: String? {
        let samples = cardioSets.compactMap { set -> (distance: Double, unit: DistanceUnit)? in
            guard let distance = set.distance else { return nil }
            return (distance, set.distanceUnit)
        }
        guard !samples.isEmpty else { return nil }

        let units = Set(samples.map(\.unit))
        if units.count == 1, let unit = units.first {
            let total = samples.reduce(0.0) { $0 + $1.distance }
            return "\(SetDisplayFormatter.formatDecimal(total)) \(unit.rawValue)"
        }

        let totalKilometers = samples.reduce(0.0) { result, sample in
            result + (sample.unit == .km ? sample.distance : sample.distance * 1.60934)
        }
        return "\(SetDisplayFormatter.formatDecimal(totalKilometers)) km (mixed units)"
    }

    private var cardioTotalDurationLabel: String? {
        let totalSeconds = cardioSets.compactMap(\.durationSeconds).reduce(0, +)
        guard totalSeconds > 0 else { return nil }
        return formattedDuration(totalSeconds)
    }

    private var cardioAveragePaceLabel: String? {
        let paces = cardioSets.compactMap { set -> Int? in
            let resolved = SetDisplayFormatter.resolvePaceSeconds(
                explicitPaceSeconds: set.paceSeconds,
                durationSeconds: set.durationSeconds,
                distance: set.distance
            )
            guard let resolved else { return nil }
            return SetDisplayFormatter.paceSeconds(
                secondsPerSourceUnit: resolved,
                sourceUnit: set.distanceUnit,
                preferredDistanceUnit: selectedDistanceUnit
            )
        }
        guard !paces.isEmpty else { return nil }
        let average = paces.reduce(0, +) / paces.count
        return SetDisplayFormatter.formatPace(
            secondsPerSourceUnit: average,
            sourceUnit: selectedDistanceUnit,
            preferredDistanceUnit: selectedDistanceUnit
        )
    }

    private var displayUnit: WeightUnit {
        selectedDisplayUnit ?? dominantUnit
    }

    private var repSamples: [RepSample] {
        repSamplesCache
    }

    private var dominantUnit: WeightUnit {
        dominantUnit(from: repSamples)
    }

    private var chartPoints: [ProgressPoint] {
        chartPointsCache
    }

    private var chartYMax: Double {
        let maxValue = chartPoints.map(\.value).max() ?? 0
        if maxValue <= 0 {
            return 1
        }
        return maxValue * 1.15
    }

    private var compactTimeframe: HistoryChartTimeframe {
        switch selectedRange {
        case .days:
            return .week
        case .weeks:
            return .month
        case .months:
            return .year
        case .years:
            return .fiveYears
        }
    }

    private var chartInterval: DateInterval {
        HistoryChartCalculator.currentWindow(for: compactTimeframe, now: Date())
    }

    private var timeframeSessions: [Session] {
        sessionService.sessionsInRange(chartInterval)
    }

    private var chartXAxisStride: Calendar.Component {
        switch selectedRange {
        case .days:
            return .day
        case .weeks:
            return .weekOfYear
        case .months:
            return .month
        case .years:
            return .year
        }
    }

    private func chartXAxisLabel(_ date: Date) -> String {
        switch selectedRange {
        case .days:
            return Self.shortDateFormatter.string(from: date)
        case .weeks:
            return Self.shortDateFormatter.string(from: date)
        case .months:
            return Self.monthFormatter.string(from: date)
        case .years:
            return Self.yearFormatter.string(from: date)
        }
    }

    private func refreshSnapshotIfNeeded() {
        guard let liveExercise else { return }
        exerciseSnapshot = ExerciseDetailSnapshot(exercise: liveExercise)
    }

    private func refreshDerivedData() {
        let entries = buildMatchingEntries()
        let cardioSets = buildCardioSets(from: entries)
        let repSamples = buildRepSamples(from: entries)
        let resolvedDisplayUnit = selectedDisplayUnit ?? dominantUnit(from: repSamples)

        matchingEntriesCache = entries
        cardioSetsCache = cardioSets
        repSamplesCache = repSamples
        previousSessionsCache = buildPreviousSessions(
            from: entries,
            preferredWeightUnit: resolvedDisplayUnit
        )
        chartPointsCache = buildChartPoints(
            hasCardioProgress: exerciseSnapshot.cardio && !cardioSets.isEmpty,
            displayUnit: resolvedDisplayUnit
        )
    }

    private func buildMatchingEntries() -> [SessionEntry] {
        sessionService.sessions
            .flatMap(\.sessionEntries)
            .filter { entry in
                guard entry.exercise.id == exerciseId else { return false }
                guard let userId = sessionService.currentUser?.id else { return true }
                return entry.session.user_id == userId
            }
    }

    private func buildCardioSets(from entries: [SessionEntry]) -> [SessionSet] {
        entries
            .flatMap(\.sets)
            .filter { set in
                set.durationSeconds != nil || set.distance != nil || set.paceSeconds != nil
            }
    }

    private func buildRepSamples(from entries: [SessionEntry]) -> [RepSample] {
        var samples: [RepSample] = []

        for entry in entries {
            for sessionSet in entry.sets {
                for rep in sessionSet.sessionReps {
                    samples.append(
                        RepSample(
                            date: entry.session.timestamp,
                            weight: rep.weight,
                            unit: rep.weightUnit,
                            reps: rep.count
                        )
                    )
                }
            }
        }

        return samples
    }

    private func buildChartPoints(
        hasCardioProgress: Bool,
        displayUnit: WeightUnit
    ) -> [ProgressPoint] {
        let points: [HistoryChartPoint]
        if hasCardioProgress {
            points = ExerciseChartCalculator.cardioPoints(
                sessions: timeframeSessions,
                interval: chartInterval,
                timeframe: compactTimeframe,
                exerciseId: exerciseId,
                metric: selectedCardioTab,
                distanceUnit: selectedDistanceUnit
            )
        } else {
            points = ExerciseChartCalculator.strengthPoints(
                sessions: timeframeSessions,
                interval: chartInterval,
                timeframe: compactTimeframe,
                exerciseId: exerciseId,
                metric: selectedTab,
                displayUnit: displayUnit
            )
        }

        return points.map { ProgressPoint(date: $0.date, value: $0.value) }
    }

    private func buildPreviousSessions(
        from entries: [SessionEntry],
        preferredWeightUnit: WeightUnit
    ) -> [PreviousSessionItem] {
        let sessions = entries
            .map(\.session)
            .sorted { $0.timestamp > $1.timestamp }

        var seen = Set<UUID>()
        var result: [PreviousSessionItem] = []

        for session in sessions {
            guard !seen.contains(session.id) else { continue }
            seen.insert(session.id)

            let matchingSessionEntries = session.sessionEntries
                .filter { $0.exercise.id == exerciseId }
                .sorted { $0.order < $1.order }
            guard !matchingSessionEntries.isEmpty else { continue }

            let unitPrefs = SetDisplayUnitPreferences(
                preferredWeightUnit: preferredWeightUnit,
                preferredDistanceUnit: selectedDistanceUnit
            )
            let sets = matchingSessionEntries
                .flatMap(\.sets)
                .sorted { $0.order < $1.order }
            let meaningfulSets = sets.filter {
                SetDisplayFormatter.isMeaningfulSet($0, exerciseKind: exerciseSnapshot.setDisplayKind)
            }

            let subtitle = compactPreviousSessionSubtitle(
                for: meaningfulSets,
                exerciseKind: exerciseSnapshot.setDisplayKind,
                unitPrefs: unitPrefs
            )

            result.append(
                PreviousSessionItem(
                    sessionId: session.id,
                    timestamp: session.timestamp,
                    subtitle: subtitle
                )
            )
        }

        return result
    }

    private func dominantUnit(from samples: [RepSample]) -> WeightUnit {
        var counts: [WeightUnit: Int] = [.lb: 0, .kg: 0]
        for rep in samples {
            counts[rep.unit, default: 0] += 1
        }
        if counts[.kg, default: 0] > counts[.lb, default: 0] {
            return .kg
        }
        return .lb
    }

    private func session(for sessionId: UUID) -> Session? {
        sessionService.sessions.first { $0.id == sessionId }
    }

    private func normalizedList(_ values: [String]?) -> [String] {
        guard let values else { return [] }
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func cleanedString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: TimeInterval(seconds)) ?? "\(seconds)s"
    }

    private func addExerciseAlias() {
        let trimmed = exerciseAliasDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validate input
        if trimmed.isEmpty {
            aliasError = "Alias cannot be empty"
            return
        }
        if trimmed.count > 100 {
            aliasError = "Alias too long (max 100 characters)"
            return
        }
        
        // Check for duplicates (case-insensitive)
        if aliases.contains(where: { $0.compare(trimmed, options: .caseInsensitive) == .orderedSame }) {
            aliasError = "This alias already exists"
            return
        }
        
        // Add to list and persist
        var updatedAliases = aliases
        updatedAliases.append(trimmed)
        
        guard let liveExercise else {
            aliasError = "Exercise is no longer available"
            return
        }

        if exerciseService.setAliases(for: liveExercise, aliases: updatedAliases) {
            exerciseAliasDraft = ""
            aliasError = nil
            refreshSnapshotIfNeeded()
        } else {
            aliasError = "Failed to add alias"
        }
    }

    private func removeExerciseAlias(at index: Int) {
        guard index >= 0 && index < aliases.count else { return }
        var updatedAliases = aliases
        updatedAliases.remove(at: index)

        guard let liveExercise else {
            aliasError = "Exercise is no longer available"
            return
        }
        
        if exerciseService.setAliases(for: liveExercise, aliases: updatedAliases) {
            aliasError = nil
            refreshSnapshotIfNeeded()
        } else {
            aliasError = "Failed to remove alias"
        }
    }

    private func compactPreviousSessionSubtitle(
        for sets: [SessionSet],
        exerciseKind: SetDisplayExerciseKind,
        unitPrefs: SetDisplayUnitPreferences
    ) -> String {
        guard !sets.isEmpty else { return "No logged sets." }

        var parts: [String] = ["\(sets.count) set\(sets.count == 1 ? "" : "s")"]

        switch exerciseKind {
        case .cardio:
            let totalDuration = sets.compactMap(\.durationSeconds).filter { $0 > 0 }.reduce(0, +)
            if totalDuration > 0 {
                parts.append(formattedDuration(totalDuration))
            }

            let targetUnit = unitPrefs.preferredDistanceUnit ?? .km
            let totalDistance = sets.reduce(0.0) { result, set in
                guard let distance = set.distance, distance > 0 else { return result }
                return result + SetDisplayFormatter.convertDistance(distance, from: set.distanceUnit, to: targetUnit)
            }
            if totalDistance > 0 {
                parts.append("\(SetDisplayFormatter.formatDecimal(totalDistance)) \(targetUnit.rawValue)")
            }

            if let paceText = SetDisplayFormatter.formatPace(
                secondsPerSourceUnit: SetDisplayFormatter.resolvePaceSeconds(
                    explicitPaceSeconds: nil,
                    durationSeconds: totalDuration > 0 ? totalDuration : nil,
                    distance: totalDistance > 0 ? totalDistance : nil
                ),
                sourceUnit: targetUnit,
                preferredDistanceUnit: targetUnit
            ) {
                parts.append(paceText)
            }

        case .strength, .bodyweight:
            let targetUnit = unitPrefs.preferredWeightUnit ?? displayUnit
            let repsPerSet = sets.compactMap { set -> Double? in
                let setReps = set.sessionReps.map(\.count).filter { $0 > 0 }
                guard !setReps.isEmpty else { return nil }
                return Double(setReps.reduce(0, +))
            }
            let weightPerSet = sets.compactMap { set -> Double? in
                let setWeights = set.sessionReps.filter { $0.weight > 0 }.map {
                    $0.weight * $0.weightUnit.conversion(to: targetUnit)
                }
                guard !setWeights.isEmpty else { return nil }
                return setWeights.reduce(0.0, +) / Double(setWeights.count)
            }

            if let repsSummary = averageSummary(values: repsPerSet, suffix: " reps") {
                if let weightSummary = averageSummary(values: weightPerSet, suffix: " \(targetUnit.name)") {
                    parts.append("\(repsSummary) @ \(weightSummary)")
                } else {
                    parts.append(repsSummary)
                }
            } else if let weightSummary = averageSummary(values: weightPerSet, suffix: " \(targetUnit.name)") {
                parts.append(weightSummary)
            }
        }

        return parts.joined(separator: " • ")
    }

    private func averageSummary(values: [Double], suffix: String) -> String? {
        guard !values.isEmpty else { return nil }
        let average = values.reduce(0.0, +) / Double(values.count)
        let allSame = values.allSatisfy { abs($0 - values[0]) < 0.0001 }
        let valueText = "\(SetDisplayFormatter.formatDecimal(average))\(suffix)"
        if allSame {
            return valueText
        }
        return "avg \(valueText)"
    }

    @ViewBuilder
    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
    }

    private var horizontalScrollHints: some View {
        HStack {
            Image(systemName: "chevron.left")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 4)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.trailing, 4)
        }
        .allowsHitTesting(false)
        .opacity(0.45)
    }

    private var previousSessions: [PreviousSessionItem] {
        previousSessionsCache
    }

}

private struct ExerciseDetailNavigationModifier: ViewModifier {
    @Binding var openedSessionTarget: ExerciseDetailView.LoggedExerciseSessionTarget?
    @Binding var showingLogExerciseSheet: Bool
    @Binding var showingAddRoutineSheet: Bool
    @Binding var showingTransferExerciseSheet: Bool
    @Binding var showingProgressionSheet: Bool

    let liveExercise: Exercise?
    let exerciseId: UUID
    let onOpenSession: (Session, SessionNavigationContext) -> Void

    func body(content: Content) -> some View {
        content
            .navigationDestination(item: $openedSessionTarget, destination: sessionDestination)
            .sheet(isPresented: $showingLogExerciseSheet) {
                logExerciseSheetContent
            }
            .sheet(isPresented: $showingAddRoutineSheet) {
                addToRoutineSheetContent
            }
            .sheet(isPresented: $showingTransferExerciseSheet) {
                ExerciseTransferToolView(initialSourceExerciseId: exerciseId)
                    .editorSheetPresentation()
            }
            .sheet(isPresented: $showingProgressionSheet) {
                progressionSheetContent
            }
    }

    private func sessionDestination(target: ExerciseDetailView.LoggedExerciseSessionTarget) -> some View {
        SingleSessionView(
            session: target.session,
            navigationContext: target.navigationContext
        )
        .appBackground()
    }

    @ViewBuilder
    private var logExerciseSheetContent: some View {
        if let liveExercise {
            LogExerciseSheetView(
                exercise: liveExercise,
                isPresented: $showingLogExerciseSheet,
                onOpenSession: onOpenSession
            )
            .presentationDetents([.height(360), .medium])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var addToRoutineSheetContent: some View {
        if let liveExercise {
            AddToRoutineSheetView(
                exercise: liveExercise,
                isPresented: $showingAddRoutineSheet
            )
            .presentationDetents([.height(360), .medium])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var progressionSheetContent: some View {
        if let liveExercise {
            NavigationStack {
                ExerciseProgressionSheetView(exercise: liveExercise)
            }
            .editorSheetPresentation()
        }
    }
}

private struct MuscleChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Color.gray.opacity(0.15))
            .clipShape(Capsule())
    }
}

struct LogExerciseSheetView: View {
    @EnvironmentObject var sessionService: SessionService
    @EnvironmentObject var seService: SessionExerciseService

    let exercise: Exercise
    @Binding var isPresented: Bool
    let onOpenSession: (Session, SessionNavigationContext) -> Void

    private var recentSessions: [Session] {
        sessionService.sessions.sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Log Exercise")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Start a new session or add to a previous one.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    Button {
                        startNewSession()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "play.fill")
                                .font(.title3)
                                .foregroundStyle(Color.green)
                            Text("Start New Session")
                                .font(.headline)
                            Spacer()
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .adaptiveCardSurface(cornerRadius: 12)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add to Previous Session")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 4)

                        if recentSessions.isEmpty {
                            Text("No previous sessions yet.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .adaptiveCardSurface(cornerRadius: 12)
                        } else {
                            ForEach(recentSessions.prefix(6), id: \.id) { session in
                                Button {
                                    addToSession(session)
                                } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(session.timestamp.formatted(date: .abbreviated, time: .shortened))
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                            if let routine = session.routine {
                                                Text(routine.name)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Text("\(session.sessionEntries.count)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(12)
                                    .frame(maxWidth: .infinity)
                                    .adaptiveCardSurface(cornerRadius: 12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            Button {
                isPresented = false
            } label: {
                Text("Cancel")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(12)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func startNewSession() {
        sessionService.selected_splitDay = nil
        sessionService.create_notes = ""
        if let newSession = sessionService.addSession() {
            seService.addExercise(session: newSession, exercise: exercise)
            let navigationContext = SessionNavigationContext.loggingContext(for: newSession, exerciseId: exercise.id)
            isPresented = false
            DispatchQueue.main.async {
                onOpenSession(newSession, navigationContext)
            }
            return
        }
        isPresented = false
    }

    private func addToSession(_ session: Session) {
        seService.addExercise(session: session, exercise: exercise)
        let navigationContext = SessionNavigationContext.loggingContext(for: session, exerciseId: exercise.id)
        isPresented = false
        DispatchQueue.main.async {
            onOpenSession(session, navigationContext)
        }
    }
}

struct AddToRoutineSheetView: View {
    @EnvironmentObject var splitDayService: RoutineService
    @EnvironmentObject var esdService: ExerciseSplitDayService

    let exercise: Exercise
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Add to Routine")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Choose a routine to add this exercise to.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    if splitDayService.routines.isEmpty {
                        Text("No routines yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .adaptiveCardSurface(cornerRadius: 12)
                    } else {
                        ForEach(splitDayService.routines, id: \.id) { routine in
                            Button {
                                addToRoutine(routine)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(Color.green)
                                    Text(routine.name)
                                        .font(.headline)
                                    Spacer()
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity)
                                .adaptiveCardSurface(cornerRadius: 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            Button {
                isPresented = false
            } label: {
                Text("Cancel")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(12)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func addToRoutine(_ routine: Routine) {
        esdService.addExercise(routine: routine, exercise: exercise)
        esdService.saveChanges()
        isPresented = false
    }
}

struct SingleExerciseLabelView: View {
    @Bindable var exercise: Exercise
    @State var orderInSplit: Int? = nil
    var subtitleText: String? = nil

    var body : some View {
        VStack (alignment: .leading, spacing: 4) {
            ZStack {
                if (exercise.isUserCreated) {
                    VStack(alignment: .leading) {
                        Text(exercise.name)
                        HStack {
                            if let subtitleText, !subtitleText.isEmpty {
                                Text(subtitleText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                if (orderInSplit != nil) {
                                    Text("Order \((orderInSplit ?? 0)+1)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }

                                Text(exercise.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    DetailedExerciseLabelView(
                        exercise: exercise,
                        orderInSplit: orderInSplit,
                        subtitleText: subtitleText
                    )
                }
            }
        }
        .padding(8)
        .cornerRadius(12)
    }
}

struct DetailedExerciseLabelView: View {
    @EnvironmentObject var exerciseService: ExerciseService
    @Bindable var exercise: Exercise
    @State var orderInSplit: Int? = nil
    var subtitleText: String? = nil
    
    var body: some View {
        HStack {
//                            Text(apiExercise.images.first ?? "")
            if let thumbnailURL = exerciseService.thumbnailURL(for: exercise) {
                CachedMediaView(url: thumbnailURL)
//                    .resizable()
                    .scaledToFill()
                    .frame(width: 45, height: 45)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .clipped()
                    .padding(.trailing, 8) // Add space between the image and text


            }
             

            VStack {
                HStack {
                    Text(exercise.name)
                    Spacer()
                }
                if let subtitleText, !subtitleText.isEmpty {
                    HStack {
                        Text(subtitleText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else if let orderInSplit = orderInSplit {
                    HStack {
                        Text("Order \((orderInSplit)+1)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
        }
    }
}

struct GIFView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = false
        webView.backgroundColor = .clear
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
