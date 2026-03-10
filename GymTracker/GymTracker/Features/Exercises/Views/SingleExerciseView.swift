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

struct SingleExerciseView: View {
    @Bindable var exercise: Exercise
    @EnvironmentObject var exerciseService: ExerciseService
    
    var body: some View {
        ExerciseDetailView(exercise: exercise)
            .navigationTitle(exercise.name)
            .toolbar {
                if exercise.isArchived {
                    Button("Restore") {
                        do {
                            try exerciseService.restore(exercise)
                            exerciseService.loadExercises()
                        } catch {
                            print("Failed to restore exercise: \(error)")
                        }
                    }
                }
            }
    }
}

struct ExerciseDetailView: View {
    let exercise: Exercise
    @EnvironmentObject var exerciseService: ExerciseService
    @EnvironmentObject var sessionService: SessionService
    @EnvironmentObject var seService: SessionExerciseService

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
    @State private var exerciseAliasDraft = ""
    @State private var isEditingAliases = false
    @State private var aliasError: String? = nil
    @StateObject private var sessionExerciseDraftStore = SessionExerciseDraftStore()
    private let previousLogsSectionID = "previous-logs-section"
    
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


    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                
                if let gifURL = exerciseService.gifURL(for: exercise) {
                    CachedMediaView(url: gifURL)
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                }

#if DEBUG
                debugIdentityCard
#endif

                if hasExerciseInfo {
                    DisclosureGroup(isExpanded: $showExerciseData) {
                        VStack(alignment: .leading, spacing: 12) {
                            detailRow("Exercise Type", exercise.exerciseType.name)

                            if let equipment = cleanedString(exercise.equipment) {
                                detailRow("Equipment", equipment)
                            }

                            if exercise.cardio {
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

                            if !primaryMuscles.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Primary Muscles")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(primaryMuscles, id: \.self) { muscle in
                                                MuscleChip(text: muscle)
                                            }
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                            }

                            if !secondaryMuscles.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Secondary Muscles")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(secondaryMuscles, id: \.self) { muscle in
                                                MuscleChip(text: muscle)
                                            }
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                            }
                        }
                        .padding(.top, 4)
                    } label: {
                        Text("Exercise Data")
                            .font(.headline)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                
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
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                
                DisclosureGroup(isExpanded: $showProgress) {
                    VStack(alignment: .leading, spacing: 10) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                if hasCardioProgress {
                                    ForEach(CardioProgressMetric.allCases) { tab in
                                        Button {
                                            selectedCardioTab = tab
                                        } label: {
                                            Text(tab.title)
                                                .font(.subheadline)
                                                .padding(.vertical, 6)
                                                .padding(.horizontal, 12)
                                                .background(selectedCardioTab == tab
                                                            ? Color.green.opacity(0.2)
                                                            : Color.gray.opacity(0.1))
                                                .cornerRadius(8)
                                                .foregroundColor(selectedCardioTab == tab ? .green : .primary)
                                        }
                                    }
                                } else {
                                    ForEach(ProgressMetric.allCases) { tab in
                                        Button {
                                            selectedTab = tab
                                        } label: {
                                            Text(tab.title)
                                                .font(.subheadline)
                                                .padding(.vertical, 6)
                                                .padding(.horizontal, 12)
                                                .background(selectedTab == tab
                                                            ? Color.green.opacity(0.2)
                                                            : Color.gray.opacity(0.1))
                                                .cornerRadius(8)
                                                .foregroundColor(selectedTab == tab ? .green : .primary)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .overlay(horizontalScrollHints)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(ProgressRange.allCases) { range in
                                    Button {
                                        selectedRange = range
                                    } label: {
                                        Text(range.rawValue)
                                            .font(.subheadline)
                                            .padding(.vertical, 6)
                                            .padding(.horizontal, 12)
                                            .background(selectedRange == range
                                                        ? Color.green.opacity(0.2)
                                                        : Color.gray.opacity(0.1))
                                            .cornerRadius(8)
                                            .foregroundColor(selectedRange == range ? .green : .primary)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .overlay(horizontalScrollHints)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                if hasCardioProgress {
                                    ForEach([DistanceUnit.km, DistanceUnit.mi], id: \.rawValue) { unit in
                                        Button {
                                            selectedDistanceUnit = unit
                                        } label: {
                                            Text(unit.rawValue.uppercased())
                                                .font(.subheadline)
                                                .padding(.vertical, 6)
                                                .padding(.horizontal, 12)
                                                .background(selectedDistanceUnit == unit
                                                            ? Color.green.opacity(0.2)
                                                            : Color.gray.opacity(0.1))
                                                .cornerRadius(8)
                                                .foregroundColor(selectedDistanceUnit == unit ? .green : .primary)
                                        }
                                    }
                                } else {
                                    ForEach(WeightUnit.allCases) { unit in
                                        Button {
                                            selectedDisplayUnit = unit
                                        } label: {
                                            Text(unit.name + "s")
                                                .font(.subheadline)
                                                .padding(.vertical, 6)
                                                .padding(.horizontal, 12)
                                                .background(displayUnit == unit
                                                            ? Color.green.opacity(0.2)
                                                            : Color.gray.opacity(0.1))
                                                .cornerRadius(8)
                                                .foregroundColor(displayUnit == unit ? .green : .primary)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .overlay(horizontalScrollHints)

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

                        NavigationLink {
                            ExerciseHistoryChartView(exercise: exercise)
                                .appBackground()
                        } label: {
                            Label("Open Full Chart", systemImage: "chart.bar.xaxis")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 6)
                } label: {
                    Text("Your Progress")
                        .font(.headline)
                        .foregroundStyle(.tint)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                
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
                .padding(.horizontal)
                .padding(.bottom, 10)
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
                .padding(.horizontal)
                .padding(.bottom, 12)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Previous Logs")
                        .font(.headline)
                        .padding(.horizontal)
                        .id(previousLogsSectionID)

                    if previousSessions.isEmpty {
                        Text("No previous logs yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.1))
                            )
                            .padding(.horizontal)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(previousSessions, id: \.session.id) { item in
                                NavigationLink {
                                    SessionExerciseView(
                                        sessionEntry: item.sessionEntry,
                                        navigationContext: .fromExerciseHistory(
                                            sessionId: item.session.id,
                                            exerciseId: exercise.id
                                        )
                                    )
                                    .appBackground()
                                    .environmentObject(sessionExerciseDraftStore)
                                } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.session.timestamp.formatted(date: .abbreviated, time: .omitted))
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
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.gray.opacity(0.1))
                                    )
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal)
                            }
                        }
                        .padding(.bottom, 12)
                    }
                }

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
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    NavigationLink {
                        ExerciseHistoryChartView(exercise: exercise)
                            .appBackground()
                    } label: {
                        Label("Charts", systemImage: "chart.bar.xaxis")
                    }
                }
                
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isEditingAliases.toggle()
                    } label: {
                        Label(isEditingAliases ? "Done Editing" : "Edit", systemImage: isEditingAliases ? "checkmark.circle" : "pencil")
                    }

                    Button {
                        withAnimation(.easeInOut) {
                            proxy.scrollTo(previousLogsSectionID, anchor: .top)
                        }
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                }
            }
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.85, green: 0.1, blue: 0.1),//.red,
                    Color.clear//gray.opacity(0.3)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 400)
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
        )
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingLogExerciseSheet) {
            LogExerciseSheetView(
                exercise: exercise,
                isPresented: $showingLogExerciseSheet
            )
            .presentationDetents([.height(360), .medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAddRoutineSheet) {
            AddToRoutineSheetView(
                exercise: exercise,
                isPresented: $showingAddRoutineSheet
            )
            .presentationDetents([.height(360), .medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingTransferExerciseSheet) {
            ExerciseTransferToolView(initialSourceExerciseId: exercise.id)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            sessionService.loadSessions()
            if selectedDisplayUnit == nil {
                selectedDisplayUnit = dominantUnit
            }
            exerciseAliasDraft = ""
            isEditingAliases = false
        }
    }

    private var matchingEntries: [SessionEntry] {
        sessionService.sessions
            .flatMap(\.sessionEntries)
            .filter { entry in
                guard entry.exercise.id == exercise.id else { return false }
                guard let userId = sessionService.currentUser?.id else { return true }
                return entry.session.user_id == userId
            }
    }

    private var primaryMuscles: [String] {
        normalizedList(exercise.primary_muscles)
    }

    private var secondaryMuscles: [String] {
        normalizedList(exercise.secondary_muscles)
    }

    private var aliases: [String] {
        normalizedList(exercise.aliases)
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
        normalizedList(exercise.instructions)
    }

    private var hasExerciseInfo: Bool {
        cleanedString(exercise.equipment) != nil ||
        !aliases.isEmpty ||
        !primaryMuscles.isEmpty ||
        !secondaryMuscles.isEmpty ||
        !cardioSets.isEmpty
    }

    private var cardioSets: [SessionSet] {
        matchingEntries
            .flatMap(\.sets)
            .filter { set in
                set.durationSeconds != nil || set.distance != nil || set.paceSeconds != nil
            }
    }

    private var hasCardioProgress: Bool {
        exercise.cardio && !cardioSets.isEmpty
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
        var samples: [RepSample] = []
        for entry in matchingEntries {
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

    private var dominantUnit: WeightUnit {
        var counts: [WeightUnit: Int] = [.lb: 0, .kg: 0]
        for rep in repSamples {
            counts[rep.unit, default: 0] += 1
        }
        if counts[.kg, default: 0] > counts[.lb, default: 0] {
            return .kg
        }
        return .lb
    }

    private var chartPoints: [ProgressPoint] {
        let points: [HistoryChartPoint]
        if hasCardioProgress {
            points = ExerciseChartCalculator.cardioPoints(
                sessions: timeframeSessions,
                interval: chartInterval,
                timeframe: compactTimeframe,
                exerciseId: exercise.id,
                metric: selectedCardioTab,
                distanceUnit: selectedDistanceUnit
            )
        } else {
            points = ExerciseChartCalculator.strengthPoints(
                sessions: timeframeSessions,
                interval: chartInterval,
                timeframe: compactTimeframe,
                exerciseId: exercise.id,
                metric: selectedTab,
                displayUnit: displayUnit
            )
        }
        return points.map { ProgressPoint(date: $0.date, value: $0.value) }
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
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        switch selectedRange {
        case .days:
            formatter.setLocalizedDateFormatFromTemplate("MMM d")
        case .weeks:
            formatter.setLocalizedDateFormatFromTemplate("MMM d")
        case .months:
            formatter.setLocalizedDateFormatFromTemplate("MMM")
        case .years:
            formatter.setLocalizedDateFormatFromTemplate("yyyy")
        }
        return formatter.string(from: date)
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
        
        if exerciseService.setAliases(for: exercise, aliases: updatedAliases) {
            exerciseAliasDraft = ""
            aliasError = nil
        } else {
            aliasError = "Failed to add alias"
        }
    }

    private func removeExerciseAlias(at index: Int) {
        guard index >= 0 && index < aliases.count else { return }
        var updatedAliases = aliases
        updatedAliases.remove(at: index)
        
        if exerciseService.setAliases(for: exercise, aliases: updatedAliases) {
            aliasError = nil
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

#if DEBUG
    private var debugIdentityCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Debug Identity")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Text("Exercise ID: \(exercise.id.uuidString)")
                .font(.caption2)
                .textSelection(.enabled)
            Text("npId: \(exercise.npId ?? "nil")")
                .font(.caption2)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }
#endif

    private struct PreviousSessionItem {
        let session: Session
        let sessionEntry: SessionEntry
        let subtitle: String
    }

    private var previousSessions: [PreviousSessionItem] {
        let sessions = matchingEntries
            .map { $0.session }
            .sorted { $0.timestamp > $1.timestamp }

        var seen = Set<UUID>()
        var result: [PreviousSessionItem] = []

        for session in sessions {
            guard !seen.contains(session.id) else { continue }
            seen.insert(session.id)

            let matchingSessionEntries = session.sessionEntries
                .filter { $0.exercise.id == exercise.id }
                .sorted { $0.order < $1.order }
            guard let focusedEntry = matchingSessionEntries.first else { continue }

            let unitPrefs = SetDisplayUnitPreferences(
                preferredWeightUnit: displayUnit,
                preferredDistanceUnit: selectedDistanceUnit
            )
            let sets = matchingSessionEntries
                .flatMap(\.sets)
                .sorted { $0.order < $1.order }
            let meaningfulSets = sets.filter {
                SetDisplayFormatter.isMeaningfulSet($0, exerciseKind: exercise.setDisplayKind)
            }

            let subtitle = compactPreviousSessionSubtitle(
                for: meaningfulSets,
                exerciseKind: exercise.setDisplayKind,
                unitPrefs: unitPrefs
            )

            result.append(
                PreviousSessionItem(
                    session: session,
                    sessionEntry: focusedEntry,
                    subtitle: subtitle
                )
            )
        }

        return result
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
                        .glassEffect(in: .rect(cornerRadius: 12.0))
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
                                .glassEffect(in: .rect(cornerRadius: 12.0))
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
                                    .glassEffect(in: .rect(cornerRadius: 12.0))
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
        }
        isPresented = false
    }

    private func addToSession(_ session: Session) {
        seService.addExercise(session: session, exercise: exercise)
        isPresented = false
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
                            .glassEffect(in: .rect(cornerRadius: 12.0))
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
                                .glassEffect(in: .rect(cornerRadius: 12.0))
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
//        .background/*(*/Color.gray.opacity(0.1))
        .cornerRadius(12)
//        .padding(.vertical, 4)
//        .padding(.horizontal, 8)
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
