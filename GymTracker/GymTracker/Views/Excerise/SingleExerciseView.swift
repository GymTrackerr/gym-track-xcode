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

struct SingleExerciseView: View {
    @Bindable var exercise: Exercise
    
    var body: some View {
        VStack {
            if (exercise.isUserCreated) {
                VStack(alignment: .leading) {
                    Text("Exercise: \(exercise.name)")
                    Text("Alises: \(exercise.aliases?.joined(separator: ", ") ?? "")")
                    Text("Muscle Groups: \(exercise.primary_muscles?.joined(separator: ", ") ?? "")")
                    Text("Date: \(exercise.timestamp.formatted(date: .numeric, time: .omitted))")
                    Text("Exercise Type: \(exercise.exerciseType.name)")
                }
                .padding()
                Spacer()
            } else {
                ExerciseDetailView(exercise: exercise)
            }
        }
        .navigationTitle(exercise.name)
    }
}

struct ExerciseDetailView: View {
    let exercise: Exercise
    @EnvironmentObject var exerciseService: ExerciseService
    @EnvironmentObject var sessionService: SessionService
    @EnvironmentObject var seService: SessionExerciseService

    @State private var showHowToPerform = true
    @State private var showProgress = true
    @State private var selectedTab = "Max Weight"
    @State private var selectedRange: ProgressRange = .months
    @State private var selectedDisplayUnit: WeightUnit? = nil
    @State private var showingLogExerciseSheet = false
    @State private var showingAddRoutineSheet = false
    
    private struct RepSample {
        let date: Date
        let weight: Double
        let unit: WeightUnit
        let reps: Int
    }

    private struct ProgressPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                
                if let gifURL = exerciseService.gifURL(for: exercise) {
                    CachedMediaView(url: gifURL)
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                }
                
                DisclosureGroup(isExpanded: $showHowToPerform) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let instructions = exercise.instructions {
                            ForEach(Array(instructions.enumerated()), id: \.offset) { i, step in
                                Text("\(i + 1). \(step)")
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
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
                
                DisclosureGroup(isExpanded: $showProgress) {
                    VStack(alignment: .leading, spacing: 10) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(["Max Weight", "Average Weight", "Total Volume", "Total Reps", "Average Reps"], id: \.self) { tab in
                                    Button {
                                        selectedTab = tab
                                    } label: {
                                        Text(tab)
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
                            .padding(.vertical, 2)
                        }
                        .overlay(horizontalScrollHints)

                        Chart(progressPoints) { point in
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
                    .padding(.top, 6)
                } label: {
                    Text("Your Progress")
                        .font(.headline)
                        .foregroundColor(.blue)
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
                    .background(Color(.blue))
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
                    .background(Color(.blue))
                    .cornerRadius(14)
                }
                .padding(.horizontal)
                .padding(.bottom, 12)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Previous Sessions")
                        .font(.headline)
                        .padding(.horizontal)

                    if previousSessions.isEmpty {
                        Text("No previous sessions yet.")
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
                                    SingleSessionView(session: item.session).appBackground()
                                } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.session.timestamp.formatted(date: .abbreviated, time: .omitted))
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                            Text("Exercise Volume: \(item.volume) \(dominantUnit.name)")
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
        .onAppear {
            if selectedDisplayUnit == nil {
                selectedDisplayUnit = dominantUnit
            }
        }
    }

    private var matchingEntries: [SessionEntry] {
        sessionService.sessions
            .flatMap { $0.sessionEntries }
            .filter { $0.exercise.id == exercise.id }
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

    private var progressPoints: [ProgressPoint] {
        let samples = repSamples
        guard !samples.isEmpty else { return [] }

        let calendar = Calendar.current
        let endDate = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()

        let bucketComponent: Calendar.Component
        let bucketCount: Int
        let startDate: Date

        switch selectedRange {
        case .days:
            bucketComponent = .day
            bucketCount = 7
            startDate = calendar.date(byAdding: .day, value: -(bucketCount - 1), to: endDate) ?? endDate
        case .weeks:
            bucketComponent = .weekOfYear
            bucketCount = 8
            startDate = calendar.date(byAdding: .weekOfYear, value: -(bucketCount - 1), to: endDate) ?? endDate
        case .months:
            bucketComponent = .month
            bucketCount = 6
            startDate = calendar.date(byAdding: .month, value: -(bucketCount - 1), to: endDate) ?? endDate
        case .years:
            bucketComponent = .year
            bucketCount = 5
            startDate = calendar.date(byAdding: .year, value: -(bucketCount - 1), to: endDate) ?? endDate
        }

        let bucketStartFor: (Date) -> Date = { date in
            switch bucketComponent {
            case .day:
                return calendar.startOfDay(for: date)
            case .weekOfYear:
                return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
            case .month:
                return calendar.dateInterval(of: .month, for: date)?.start ?? date
            case .year:
                return calendar.dateInterval(of: .year, for: date)?.start ?? date
            default:
                return date
            }
        }

        var buckets: [Date] = []
        var current = bucketStartFor(startDate)
        for _ in 0..<bucketCount {
            buckets.append(current)
            if let next = calendar.date(byAdding: bucketComponent, value: 1, to: current) {
                current = next
            }
        }

        return buckets.map { bucketStart in
            let bucketEnd = calendar.date(byAdding: bucketComponent, value: 1, to: bucketStart) ?? bucketStart
            let items = samples.filter { $0.date >= bucketStart && $0.date < bucketEnd }
            let value: Double

            switch selectedTab {
            case "Max Weight":
                value = items.map { sample in
                    convertWeight(sample.weight, from: sample.unit, to: displayUnit)
                }.max() ?? 0
            case "Average Weight":
                let totalWeight = items.reduce(0.0) { result, sample in
                    result + convertWeight(sample.weight, from: sample.unit, to: displayUnit)
                }
                value = items.isEmpty ? 0 : totalWeight / Double(items.count)
            case "Total Volume":
                value = items.reduce(0) { result, sample in
                    let weight = convertWeight(sample.weight, from: sample.unit, to: displayUnit)
                    return result + (weight * Double(sample.reps))
                }
            case "Total Reps":
                value = Double(items.reduce(0) { $0 + $1.reps })
            case "Average Reps":
                let totalReps = items.reduce(0) { $0 + $1.reps }
                value = items.isEmpty ? 0 : Double(totalReps) / Double(items.count)
            default:
                value = 0
            }

            return ProgressPoint(date: bucketStart, value: value)
        }
    }

    private var chartYMax: Double {
        let maxValue = progressPoints.map(\.value).max() ?? 0
        if maxValue <= 0 {
            return 1
        }
        return maxValue * 1.15
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

    private func convertWeight(_ value: Double, from source: WeightUnit, to target: WeightUnit) -> Double {
        value * source.conversion(to: target)
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

    private struct PreviousSessionItem {
        let session: Session
        let volume: Int
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

            var totalVolume: Double = 0
            for entry in session.sessionEntries where entry.exercise.id == exercise.id {
                for sessionSet in entry.sets {
                    for rep in sessionSet.sessionReps {
                        let weight = convertWeight(rep.weight, from: rep.weightUnit, to: dominantUnit)
                        totalVolume += weight * Double(rep.count)
                    }
                }
            }

            result.append(
                PreviousSessionItem(
                    session: session,
                    volume: Int(round(totalVolume))
                )
            )
        }

        return result
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

    var body : some View {
        VStack (alignment: .leading, spacing: 4) {
            ZStack {
                if (exercise.isUserCreated) {
                    VStack(alignment: .leading) {
                        Text(exercise.name)
                        HStack {
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
                    .padding(.vertical, 4)
                } else {
                    DetailedExerciseLabelView(exercise: exercise, orderInSplit: orderInSplit)
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
                if let orderInSplit = orderInSplit {
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
