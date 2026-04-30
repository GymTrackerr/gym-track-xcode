//
//  SingleDayView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftUI

private struct OpenedSessionEntryTarget: Identifiable, Equatable, Hashable {
    let id: UUID
}

// TODO: remove / add exercises from (+) menu

struct SingleSessionView: View {
    @EnvironmentObject var seService: SessionExerciseService
    @EnvironmentObject var esdService: ExerciseSplitDayService
    @EnvironmentObject var sessionService: SessionService
    @EnvironmentObject var exerciseService: ExerciseService
    @EnvironmentObject var splitDayService: RoutineService
    @EnvironmentObject var timerService: TimerService

    @Bindable var session: Session
    let navigationContext: SessionNavigationContext
    @Environment(\.editMode) private var editMode
    @State var syncingSplit: Bool = false
    @State private var isUnlockedForEditing: Bool = false
    @StateObject private var sessionExerciseDraftStore = SessionExerciseDraftStore()
    @State private var trackedSessionEntryIds: Set<UUID> = []
    @State private var openedSessionEntryTarget: OpenedSessionEntryTarget?
    @State private var hasAutoOpenedPreferredExercise = false

    private let cardCornerRadius: CGFloat = 16
    private let accentGreen = Color.green
    private let softGreen = Color.green.opacity(0.12)

    init(session: Session, navigationContext: SessionNavigationContext? = nil) {
        self.session = session
        self.navigationContext = navigationContext ?? SessionNavigationContext.forSession(session)
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 16) {
                if editMode?.wrappedValue == .inactive {
                    sessionSummaryCard
                } else {
                    sessionEditCard
                }
            }
            .padding(.horizontal)
            .padding(.top, 6)

            VStack(alignment: .leading, spacing: 8) {
                Text("Today's Exercises")
                    .font(.headline)
                    .padding(.horizontal)

                List {
                    ForEach(sortedSessionEntries, id: \.id) { sessionEntry in
                        sessionEntryLink(for: sessionEntry)
                    }
                    .onDelete(perform: removeExercise)
                    .onMove(perform: moveExercise)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .foregroundStyle(.primary)
        
        .navigationTitle(sessionTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
        #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                if canModifySessionExercises {
                    EditButton()
                } else if navigationContext.allowsUnlock {
                    Button("Unlock") {
                        isUnlockedForEditing = true
                    }
                }
            }
        #endif
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    TimerView()
                } label: {
                    Label(timerButtonTitle, systemImage: "timer")
                }
            }
            ToolbarItem {
                if canModifySessionExercises {
                    Button {
                        exerciseService.editingContent = ""
                        seService.addingExerciseSession = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $seService.addingExerciseSession) {
            addingExerciseSessionView(session: session)
        }
        .navigationDestination(item: $openedSessionEntryTarget) { target in
            if let sessionEntry = session.sessionEntries.first(where: { $0.id == target.id }) {
                SessionExerciseView(
                    sessionEntry: sessionEntry,
                    navigationContext: navigationContext
                )
                .appBackground()
                .environmentObject(sessionExerciseDraftStore)
            } else {
                EmptyView()
            }
        }
        .onAppear {
            trackedSessionEntryIds = Set(session.sessionEntries.map(\.id))
            autoOpenPreferredExerciseIfNeeded()
        }
        .onChange(of: session.sessionEntries.map(\.id)) { _, newIds in
            let newSet = Set(newIds)
            let removed = trackedSessionEntryIds.subtracting(newSet)
            if !removed.isEmpty {
                sessionExerciseDraftStore.clearDrafts(for: Array(removed))
            }
            trackedSessionEntryIds = newSet
            autoOpenPreferredExerciseIfNeeded()
        }
        .onChange(of: session.timestampDone) { oldValue, newValue in
            let justFinished = oldValue == session.timestamp && newValue != session.timestamp
            if justFinished {
                sessionExerciseDraftStore.clearDrafts(for: session.sessionEntries.map(\.id))
            }
        }
    }
    
    func removeExercise(offsets: IndexSet) {
        guard canModifySessionExercises else { return }
        let sortedEntries = session.sessionEntries.sorted { $0.order < $1.order }
        let removedIds = offsets.compactMap { index -> UUID? in
            guard sortedEntries.indices.contains(index) else { return nil }
            return sortedEntries[index].id
        }
        sessionExerciseDraftStore.clearDrafts(for: removedIds)
        seService.removeExercise(session: session, offsets: offsets)
    }
    
    func moveExercise(from source: IndexSet, to destination: Int) {
        guard canModifySessionExercises else { return }
        withTransaction(Transaction(animation: .default)) {
            seService.moveExercise(session: session, from: source, to: destination)
        }
    }

    // MARK: - Draft Cleanup Helpers

    /// Removes a single exercise and clears its draft state
    private func removeExerciseAndCleanupDraft(_ sessionEntry: SessionEntry) {
        sessionExerciseDraftStore.clearDraft(for: sessionEntry.id)
        seService.removeExercise(session: session, sessionEntry: sessionEntry)
    }

    private var isSessionIncomplete: Bool {
        session.timestampDone == session.timestamp
    }

    private var isSessionCompleted: Bool {
        session.timestampDone != session.timestamp
    }

    private var sessionTitle: String {
        let dateStyle = Date.FormatStyle(date: .numeric, time: .omitted)
        return "Session \(session.timestamp.formatted(dateStyle))"
    }

    private var sessionTimeDetail: String {
        let dateStyle = Date.FormatStyle(date: .long, time: .omitted)
        let timeStyle = Date.FormatStyle(date: .omitted, time: .shortened)
        let dateText = session.timestamp.formatted(dateStyle)
        let startTime = session.timestamp.formatted(timeStyle)

        if isSessionCompleted {
            let endTime = session.timestampDone.formatted(timeStyle)
            return "\(dateText) at \(startTime) - \(endTime)"
        }

        return "\(dateText) at \(startTime)"
    }

    private var timerButtonTitle: String {
        if timerService.timer != nil {
            return "Timer \(timerService.formatted)"
        }

        return "Timer"
    }

    private var canModifySessionExercises: Bool {
        navigationContext.isEditableByDefault || isUnlockedForEditing
    }

    private var sortedSessionEntries: [SessionEntry] {
        session.sessionEntries.sorted { $0.order < $1.order }
    }

    @ViewBuilder
    private func sessionEntryLink(for sessionEntry: SessionEntry) -> some View {
        let destinationContext = SessionNavigationContext.forSession(session)
        let completionLabel = sessionEntry.isCompleted ? "Uncheck" : "Complete"
        let completionSystemImage = sessionEntry.isCompleted ? "pencil.slash" : "checkmark"
        let completionTint: Color = sessionEntry.isCompleted ? .orange : .green
        let completionEdge: HorizontalEdge = (editMode?.wrappedValue == .inactive) ? .leading : .trailing
        let allowsFullSwipe = (editMode?.wrappedValue == .inactive)

        NavigationLink {
            SessionExerciseView(
                sessionEntry: sessionEntry,
                navigationContext: destinationContext
            )
            .appBackground()
            .environmentObject(sessionExerciseDraftStore)
        } label: {
            sessionEntryLabel(for: sessionEntry)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(sessionEntryRowBackground)
        .swipeActions(edge: completionEdge, allowsFullSwipe: allowsFullSwipe) {
            if canModifySessionExercises {
                Button {
                    seService.toggleCompletion(sessionEntry: sessionEntry)
                } label: {
                    Label(completionLabel, systemImage: completionSystemImage)
                }
                .tint(completionTint)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: allowsFullSwipe) {
            if canModifySessionExercises {
                Button {
                    removeExerciseAndCleanupDraft(sessionEntry)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .tint(.red)
            }
        }
    }

    private func sessionEntryLabel(for sessionEntry: SessionEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: sessionEntry.isCompleted ? "checkmark.arrow.trianglehead.counterclockwise" : "square.and.pencil")
                .foregroundColor(sessionEntry.isCompleted ? .green : .secondary)
                .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 4) {
                SingleExerciseLabelView(
                    exercise: sessionEntry.exercise,
                    orderInSplit: sessionEntry.order,
                    subtitleText: summaryText(for: sessionEntry)
                )
                .id(sessionEntry.order)
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var sessionEntryRowBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.gray.opacity(0.1))
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
    }

    private func autoOpenPreferredExerciseIfNeeded() {
        guard hasAutoOpenedPreferredExercise == false else { return }
        guard let preferredExerciseId = navigationContext.preferredExerciseId else { return }
        guard let matchedEntry = session.sessionEntries.first(where: { $0.exercise.id == preferredExerciseId }) else {
            return
        }

        hasAutoOpenedPreferredExercise = true
        openedSessionEntryTarget = OpenedSessionEntryTarget(id: matchedEntry.id)
    }

    private func summaryText(for sessionEntry: SessionEntry) -> String? {
        if sessionEntry.exercise.cardio {
            return cardioSummaryText(for: sessionEntry)
        }
        return strengthSummaryText(for: sessionEntry)
    }

    private func strengthSummaryText(for sessionEntry: SessionEntry) -> String? {
        let exerciseKind = sessionEntry.exercise.setDisplayKind
        let meaningfulSets = sessionEntry.sets.filter {
            SetDisplayFormatter.isMeaningfulSet($0, exerciseKind: exerciseKind)
        }
        guard !meaningfulSets.isEmpty else { return nil }

        let repsPerSet = meaningfulSets.compactMap { sessionSet -> Double? in
            let setReps = sessionSet.sessionReps
                .map(\.count)
                .filter { $0 > 0 }
            guard !setReps.isEmpty else { return nil }
            return Double(setReps.reduce(0, +))
        }

        let weightUnit = SetDisplayFormatter.dominantWeightUnit(in: meaningfulSets.flatMap(\.sessionReps).filter { $0.weight > 0 })
        let weightPerSet = meaningfulSets.compactMap { sessionSet -> Double? in
            let setWeights = sessionSet.sessionReps.filter { $0.weight > 0 }.map {
                $0.weight * $0.weightUnit.conversion(to: weightUnit)
            }
            guard !setWeights.isEmpty else { return nil }
            return setWeights.reduce(0.0, +) / Double(setWeights.count)
        }

        let repsSummary = metricSummary(
            values: repsPerSet,
            formattedValue: { "\(SetDisplayFormatter.formatDecimal($0))" },
            includeAverageLabelWhenNeeded: true
        )
        let weightSummary = metricSummary(
            values: weightPerSet,
            formattedValue: { "\(SetDisplayFormatter.formatDecimal($0))\(weightUnit.name)" },
            includeAverageLabelWhenNeeded: true
        )

        var tail = ""
        if let repsSummary, let weightSummary {
            tail = "\(repsSummary) @ \(weightSummary)"
        } else if let repsSummary {
            tail = repsSummary
        } else if let weightSummary {
            tail = weightSummary
        }

        if tail.isEmpty {
            return "\(meaningfulSets.count) sets"
        }
        return "\(meaningfulSets.count) sets - \(tail)"
    }

    private func cardioSummaryText(for sessionEntry: SessionEntry) -> String? {
        let meaningfulSets = sessionEntry.sets.filter {
            SetDisplayFormatter.isMeaningfulSet($0, exerciseKind: .cardio)
        }
        guard !meaningfulSets.isEmpty else { return nil }

        let totalDurationSeconds = meaningfulSets.reduce(0) { result, set in
            result + max(set.durationSeconds ?? 0, 0)
        }

        let distanceSamples = meaningfulSets.compactMap { set -> (distance: Double, unit: DistanceUnit)? in
            guard let distance = set.distance, distance > 0 else { return nil }
            return (distance, set.distanceUnit)
        }

        let distanceUnit = SetDisplayFormatter.dominantDistanceUnit(in: distanceSamples)
        let totalDistance = distanceSamples.reduce(0.0) { result, sample in
            result + SetDisplayFormatter.convertDistance(sample.distance, from: sample.unit, to: distanceUnit)
        }

        var parts: [String] = []
        if totalDurationSeconds > 0 {
            parts.append(SetDisplayFormatter.formatClockDuration(totalDurationSeconds))
        }
        if totalDistance > 0 {
            parts.append("\(SetDisplayFormatter.formatDecimal(totalDistance)) \(distanceUnit.rawValue)")
        }

        if let paceText = SetDisplayFormatter.formatPace(
            secondsPerSourceUnit: SetDisplayFormatter.resolvePaceSeconds(
                explicitPaceSeconds: nil,
                durationSeconds: totalDurationSeconds > 0 ? totalDurationSeconds : nil,
                distance: totalDistance > 0 ? totalDistance : nil
            ),
            sourceUnit: distanceUnit,
            preferredDistanceUnit: distanceUnit
        ) {
            parts.append(paceText)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private func metricSummary(
        values: [Double],
        formattedValue: (Double) -> String,
        includeAverageLabelWhenNeeded: Bool
    ) -> String? {
        guard !values.isEmpty else { return nil }
        let average = values.reduce(0.0, +) / Double(values.count)
        let allEqual = values.allSatisfy { abs($0 - values[0]) < 0.0001 }
        if includeAverageLabelWhenNeeded && !allEqual {
            return "avg \(formattedValue(average))"
        }
        return formattedValue(average)
    }

    private var sessionSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let routine = session.routine {
                    Text(routine.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                } else {
                    Text("Day #1")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                Spacer()
                Text(navigationContext.statusBadgeText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.gray.opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(sessionTimeDetail)
                .font(.subheadline)
                .foregroundColor(.secondary)

            if isSessionIncomplete {
                Button {
                    sessionExerciseDraftStore.clearDrafts(for: session.sessionEntries.map(\.id))
                    sessionService.finishSession(session)
                } label: {
                    Text("Finish Session")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(accentGreen)
            }

            if session.notes.trimmingCharacters(in: .whitespacesAndNewlines) != "" {
                Text(session.notes)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(softGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
        .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
    }

    private var sessionEditCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Session")
                .font(.headline)

            VStack(spacing: 12) {
                SessionSelectSplit()
                    .onChange(of: sessionService.selected_splitDay?.id) { _, _ in
                        _ = sessionService.updateSessionToSplitDay(session: session)
                    }

                TextField("Add optional notes...", text: $session.notes)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Start")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    DatePicker("Date & Time", selection: $session.timestamp, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .onChange(of: session.timestamp) { oldValue, newValue in
                            // Keep end time aligned with start time change.
                            let duration = session.timestampDone.timeIntervalSince(oldValue)
                            session.timestampDone = newValue.addingTimeInterval(duration)
                        }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("End")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    DatePicker("Date & Time", selection: $session.timestampDone, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .labelsHidden()
                }
            }

            sessionEditActionSection
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
        .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
    }

    private var sessionEditActionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let routine = session.routine {
                if routine.isArchived {
                    Button {
                        do {
                            try splitDayService.restore(routine)
                            splitDayService.loadSplitDays()
                        } catch {
                            print("Failed to restore routine: \(error)")
                        }

                    } label: {
                        Text("Restore Routine")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if syncingSplit {
                    Text("Are you sure? This action will replace all exercises with those in this session.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Button {
                            syncingSplit = false
                        } label: {
                            Text("Cancel")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            if routine.isArchived {
                                try? splitDayService.restore(routine)
                                splitDayService.loadSplitDays()
                            }
                            esdService.syncSplitWithSession(routine: routine, session: session)
                            syncingSplit = false
                        } label: {
                            Text("Confirm")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accentGreen)
                    }
                } else {
                    Button {
                        syncingSplit = true
                    } label: {
                        Text("Sync Routine with Session")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                if !syncingSplit {
                    Button {
                        syncingSplit = true
                    } label: {
                        Text("Create new Routine")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name your new split day")
                            .font(.subheadline)
                        TextField("Name", text: $splitDayService.editingContent)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack(spacing: 12) {
                        Button {
                            syncingSplit = false
                            splitDayService.editingSplit = false
                            splitDayService.editingContent = ""
                        } label: {
                            Text("Cancel")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            let newSplit = splitDayService.addSplitDay()
                            if let newSplit {
                                sessionService.updateSessionToSplitDay(session: session, routine: newSplit)
                                esdService.syncSplitWithSession(routine: newSplit, session: session)
                            }
                            syncingSplit = false
                        } label: {
                            Text("Save")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accentGreen)
                        .disabled(splitDayService.editingContent.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }
}

struct SingleSessionLabelView: View {
    @Bindable var session: Session

    private var metrics: SessionRowMetrics? {
        SessionRowMetrics(
            exerciseCount: session.sessionEntries.count,
            volumeText: SessionService.formattedPounds(SessionService.sessionVolumeInPounds(session)),
            durationText: sessionDurationText
        )
    }

    private var subtitleText: String? {
        if let routine = session.routine {
            return routine.name
        }

        if let workoutName = session.programWorkoutName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !workoutName.isEmpty {
            return workoutName
        }

        if let program = session.program {
            return program.name
        }

        return nil
    }

    private var sessionDurationText: String? {
        guard session.timestampDone > session.timestamp else { return nil }
        let duration = session.timestampDone.timeIntervalSince(session.timestamp)
        guard duration > 0 else { return nil }
        return "\(Int((duration / 60).rounded())) min"
    }

    var body : some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(session.timestamp, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                    .font(.headline)

                if let subtitleText {
                    Text(subtitleText)
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

struct SessionRowMetrics {
    let exerciseCount: Int
    let volumeText: String
    let durationText: String?
}


struct addingExerciseSessionView : View {
    @EnvironmentObject var seService: SessionExerciseService
    @EnvironmentObject var exerciseService: ExerciseService

    @State var searchResults: [Exercise] = []

    @Bindable var session: Session
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                TextField("Search or Create Exercise", text: $exerciseService.editingContent)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                Button {
                    let exerciseNew = exerciseService.addExercise()
                    DispatchQueue.main.async {
                        if let exercise = exerciseNew {
                            addExerciseEditing(exercise: exercise)
                        }
                        
                    }
                } label: {
                    Label("Add", systemImage: "plus.circle")
                        .font(.title2)
                        .padding()
                }
                .disabled(exerciseService.editingContent.trimmingCharacters(in: .whitespaces).isEmpty)
                List {
                    // TODO: ADD BUTTONS TO ADD/REMOVE EXERCISES?? -- make sure there are no sets/reps
                    ForEach(searchResults, id: \.id) { exercise in
                        Button(action: {
                            addExerciseEditing(exercise: exercise)
                        }) {
                            HStack {
                                Text("\(seService.amountAdded(session: session, exercise: exercise))")

                                Image(systemName: "plus")

                                Text(exercise.name)
                            }
                        }
                    }
                }

                .listStyle(.plain)
                Spacer()
            }
            .padding()
            .navigationTitle("Add Exercises")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        seService.confirmEditing(session: session)
                        exerciseService.editingContent = ""
                    }
                }
            
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        seService.endEditing()
                        exerciseService.editingContent = ""
                        exerciseService.editingContent = ""
                    }
                }
            }
            .onChange(of: exerciseService.editingContent) {
                performSearch()
            }
        }
        .onAppear {
            performSearch()
        }
    }
//    func removeExerciseEditing(exercise: Exercise) {
//        if (seService.isInAdding(id: exercise.id)) {
//            seService.addingExercises.removeAll { $0.id == exercise.id }
//            
//        } else {
//            seService.removingExercises.append(exercise)
//        }
//    }
    
    func addExerciseEditing(exercise: Exercise) {
        if (seService.isInRemoving(id: exercise.id)) {
            seService.removingExercises.removeAll { $0.id == exercise.id }
        } else {
            seService.addingExercises.append(exercise)
        }
    }
    
    func performSearch() {
        print("searching \(exerciseService.editingContent)")
        searchResults = exerciseService.search(query: exerciseService.editingContent)
    }
}
