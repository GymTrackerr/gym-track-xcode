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

    private let accentGreen = Color.green
    private let softGreen = Color.green.opacity(0.12)

    init(session: Session, navigationContext: SessionNavigationContext? = nil) {
        self.session = session
        self.navigationContext = navigationContext ?? SessionNavigationContext.forSession(session)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                if editMode?.wrappedValue == .inactive {
                    sessionSummaryCard
                } else {
                    sessionEditCard
                }
            }
            .padding(.top, 6)
            .screenContentPadding()

            List {
                Section {
                    ForEach(sortedSessionEntries, id: \.id) { sessionEntry in
                        sessionEntryLink(for: sessionEntry)
                    }
                    .onDelete(perform: removeExercise)
                    .onMove(perform: moveExercise)
                } header: {
                    Text(LocalizedStringResource("sessions.detail.todayExercises", defaultValue: "Today's Exercises", table: "Sessions"))
                }
            }
            .cardListScreen()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.primary)
        
        .navigationTitle(Text(sessionTitleResource))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
        #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                if canModifySessionExercises {
                    EditButton()
                } else if navigationContext.allowsUnlock {
                    Button {
                        isUnlockedForEditing = true
                    } label: {
                        Text(LocalizedStringResource("sessions.action.unlock", defaultValue: "Unlock", table: "Sessions"))
                    }
                }
            }
        #endif
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    TimerView()
                } label: {
                    Label {
                        Text(timerButtonTitleResource)
                    } icon: {
                        Image(systemName: "timer")
                    }
                }
            }
            ToolbarItem {
                if canModifySessionExercises {
                    Button {
                        exerciseService.editingContent = ""
                        seService.addingExerciseSession = true
                    } label: {
                        Label {
                            Text(LocalizedStringResource("sessions.action.addExercise", defaultValue: "Add Exercise", table: "Sessions"))
                        } icon: {
                            Image(systemName: "plus.circle")
                        }
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

    private var sessionTitleResource: LocalizedStringResource {
        let dateStyle = Date.FormatStyle(date: .numeric, time: .omitted)
        let dateText = session.timestamp.formatted(dateStyle)
        return LocalizedStringResource("sessions.detail.title", defaultValue: "Session \(dateText)", table: "Sessions")
    }

    private var sessionTimeDetailResource: LocalizedStringResource {
        let dateStyle = Date.FormatStyle(date: .long, time: .omitted)
        let timeStyle = Date.FormatStyle(date: .omitted, time: .shortened)
        let dateText = session.timestamp.formatted(dateStyle)
        let startTime = session.timestamp.formatted(timeStyle)

        if isSessionCompleted {
            let endTime = session.timestampDone.formatted(timeStyle)
            return LocalizedStringResource("sessions.detail.timeRange", defaultValue: "\(dateText) at \(startTime) - \(endTime)", table: "Sessions")
        }

        return LocalizedStringResource("sessions.detail.startTime", defaultValue: "\(dateText) at \(startTime)", table: "Sessions")
    }

    private var timerButtonTitleResource: LocalizedStringResource {
        if timerService.timer != nil {
            return LocalizedStringResource("sessions.timer.titleWithTime", defaultValue: "Timer \(timerService.formatted)", table: "Sessions")
        }

        return LocalizedStringResource("sessions.timer.title", defaultValue: "Timer", table: "Sessions")
    }

    private var statusBadgeResource: LocalizedStringResource {
        switch navigationContext {
        case .active, .activePreferred:
            return LocalizedStringResource("sessions.status.currentSession", defaultValue: "Current session", table: "Sessions")
        case .pastPreferred:
            return LocalizedStringResource("sessions.status.loggingExercise", defaultValue: "Logging exercise", table: "Sessions")
        case .past, .fromExerciseHistory:
            return LocalizedStringResource("sessions.status.pastSession", defaultValue: "Past session", table: "Sessions")
        }
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
        let completionLabel = sessionEntry.isCompleted
            ? LocalizedStringResource("sessions.action.uncheck", defaultValue: "Uncheck", table: "Sessions")
            : LocalizedStringResource("sessions.action.complete", defaultValue: "Complete", table: "Sessions")
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
        .cardListRowStyle()
        .swipeActions(edge: completionEdge, allowsFullSwipe: allowsFullSwipe) {
            if canModifySessionExercises {
                Button {
                    seService.toggleCompletion(sessionEntry: sessionEntry)
                } label: {
                    Label {
                        Text(completionLabel)
                    } icon: {
                        Image(systemName: completionSystemImage)
                    }
                }
                .tint(completionTint)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: allowsFullSwipe) {
            if canModifySessionExercises {
                Button {
                    removeExerciseAndCleanupDraft(sessionEntry)
                } label: {
                    Label {
                        Text(LocalizedStringResource("sessions.action.remove", defaultValue: "Remove", table: "Sessions"))
                    } icon: {
                        Image(systemName: "trash")
                    }
                }
                .tint(.red)
            }
        }
    }

    private func sessionEntryLabel(for sessionEntry: SessionEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: sessionEntry.isCompleted ? "checkmark.arrow.trianglehead.counterclockwise" : "square.and.pencil")
                .foregroundColor(sessionEntry.isCompleted ? .green : .secondary)
                .frame(width: 28)

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
        .cardListRowContentPadding()
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
            return String(localized: LocalizedStringResource("sessions.summary.setsOnly", defaultValue: "\(meaningfulSets.count) sets", table: "Sessions"))
        }
        return String(localized: LocalizedStringResource("sessions.summary.setsWithDetail", defaultValue: "\(meaningfulSets.count) sets - \(tail)", table: "Sessions"))
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
            let value = formattedValue(average)
            return String(localized: LocalizedStringResource("sessions.summary.averageValue", defaultValue: "avg \(value)", table: "Sessions"))
        }
        return formattedValue(average)
    }

    private var sessionSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let routine = session.routine {
                    Text(verbatim: routine.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                } else {
                    Text(LocalizedStringResource("sessions.detail.defaultDayName", defaultValue: "Day #1", table: "Sessions"))
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                Spacer()
                Text(statusBadgeResource)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.gray.opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(sessionTimeDetailResource)
                .font(.subheadline)
                .foregroundColor(.secondary)

            if isSessionIncomplete {
                Button {
                    sessionExerciseDraftStore.clearDrafts(for: session.sessionEntries.map(\.id))
                    sessionService.finishSession(session)
                } label: {
                    Text(LocalizedStringResource("sessions.edit.finishSession", defaultValue: "Finish Session", table: "Sessions"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(accentGreen)
            }

            if session.notes.trimmingCharacters(in: .whitespacesAndNewlines) != "" {
                Text(verbatim: session.notes)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(softGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .cardRowContainerStyle()
    }

    private var sessionEditCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LocalizedStringResource("sessions.edit.title", defaultValue: "Edit Session", table: "Sessions"))
                .font(.headline)

            VStack(spacing: 12) {
                SessionSelectSplit()
                    .onChange(of: sessionService.selected_splitDay?.id) { _, _ in
                        _ = sessionService.updateSessionToSplitDay(session: session)
                    }

                TextField(
                    text: $session.notes,
                    prompt: Text(LocalizedStringResource("sessions.edit.notes.placeholder", defaultValue: "Add optional notes...", table: "Sessions"))
                ) {
                    Text(LocalizedStringResource("sessions.edit.notes.label", defaultValue: "Notes", table: "Sessions"))
                }
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 8) {
                    Text(LocalizedStringResource("sessions.edit.start", defaultValue: "Start", table: "Sessions"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    DatePicker(
                        selection: $session.timestamp,
                        displayedComponents: [.date, .hourAndMinute]
                    ) {
                        Text(LocalizedStringResource("sessions.edit.dateTime", defaultValue: "Date & Time", table: "Sessions"))
                    }
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .onChange(of: session.timestamp) { oldValue, newValue in
                            // Keep end time aligned with start time change.
                            let duration = session.timestampDone.timeIntervalSince(oldValue)
                            session.timestampDone = newValue.addingTimeInterval(duration)
                        }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(LocalizedStringResource("sessions.edit.end", defaultValue: "End", table: "Sessions"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    DatePicker(
                        selection: $session.timestampDone,
                        displayedComponents: [.date, .hourAndMinute]
                    ) {
                        Text(LocalizedStringResource("sessions.edit.dateTime", defaultValue: "Date & Time", table: "Sessions"))
                    }
                        .datePickerStyle(.compact)
                        .labelsHidden()
                }
            }

            sessionEditActionSection
        }
        .cardRowContainerStyle()
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
                        Text(LocalizedStringResource("sessions.edit.restoreRoutine", defaultValue: "Restore Routine", table: "Sessions"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if syncingSplit {
                    Text(LocalizedStringResource("sessions.edit.syncWarning", defaultValue: "Are you sure? This action will replace all exercises with those in this session.", table: "Sessions"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Button {
                            syncingSplit = false
                        } label: {
                            Text(LocalizedStringResource("sessions.action.cancel", defaultValue: "Cancel", table: "Sessions"))
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
                            Text(LocalizedStringResource("sessions.action.confirm", defaultValue: "Confirm", table: "Sessions"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accentGreen)
                    }
                } else {
                    Button {
                        syncingSplit = true
                    } label: {
                        Text(LocalizedStringResource("sessions.edit.syncRoutine", defaultValue: "Sync Routine with Session", table: "Sessions"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                if !syncingSplit {
                    Button {
                        syncingSplit = true
                    } label: {
                        Text(LocalizedStringResource("sessions.edit.createRoutine", defaultValue: "Create new Routine", table: "Sessions"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizedStringResource("sessions.edit.newRoutineNamePrompt", defaultValue: "Name your new split day", table: "Sessions"))
                            .font(.subheadline)
                        TextField(
                            text: $splitDayService.editingContent,
                            prompt: Text(LocalizedStringResource("sessions.edit.name.placeholder", defaultValue: "Name", table: "Sessions"))
                        ) {
                            Text(LocalizedStringResource("sessions.edit.name.label", defaultValue: "Name", table: "Sessions"))
                        }
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack(spacing: 12) {
                        Button {
                            syncingSplit = false
                            splitDayService.editingSplit = false
                            splitDayService.editingContent = ""
                        } label: {
                            Text(LocalizedStringResource("sessions.action.cancel", defaultValue: "Cancel", table: "Sessions"))
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
                            Text(LocalizedStringResource("sessions.action.save", defaultValue: "Save", table: "Sessions"))
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
        let minutes = Int((duration / 60).rounded())
        return String(localized: LocalizedStringResource("sessions.summary.durationMinutes", defaultValue: "\(minutes) min", table: "Sessions"))
    }

    var body : some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(session.timestamp, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                    .font(.headline)

                if let subtitleText {
                    Text(verbatim: subtitleText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let metrics {
                    Text(verbatim: metadataText(metrics: metrics))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                }
            }
            .cardListRowContentPadding()
        }
    }

    private func metadataText(metrics: SessionRowMetrics) -> String {
        var components = [
            String(localized: LocalizedStringResource("sessions.summary.exerciseCount", defaultValue: "\(metrics.exerciseCount) exercises", table: "Sessions")),
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
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    ConnectedCardSection {
                        ConnectedCardRow {
                            TextField(
                                text: $exerciseService.editingContent,
                                prompt: Text(LocalizedStringResource("sessions.addExercise.search.placeholder", defaultValue: "Search or create exercise", table: "Sessions"))
                            ) {
                                Text(LocalizedStringResource("sessions.addExercise.search.label", defaultValue: "Search exercise", table: "Sessions"))
                            }
                                .textFieldStyle(.roundedBorder)
                        }

                        ConnectedCardDivider()

                        Button {
                            createAndQueueExercise()
                        } label: {
                            ConnectedCardRow {
                                Label {
                                    Text(LocalizedStringResource("sessions.action.addExercise", defaultValue: "Add Exercise", table: "Sessions"))
                                } icon: {
                                    Image(systemName: "plus.circle")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(exerciseService.editingContent.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .screenContentPadding()

                List {
                    ForEach(searchResults, id: \.id) { exercise in
                        Button(action: {
                            addExerciseEditing(exercise: exercise)
                        }) {
                            HStack {
                                Text(verbatim: "\(seService.amountAdded(session: session, exercise: exercise))")

                                Image(systemName: "plus")

                                Text(verbatim: exercise.name)
                            }
                            .cardListRowContentPadding()
                        }
                        .buttonStyle(.plain)
                        .cardListRowStyle()
                    }
                }
                .cardListScreen()
            }
            .navigationTitle(Text(LocalizedStringResource("sessions.addExercise.title", defaultValue: "Add Exercises", table: "Sessions")))
            .navigationBarTitleDisplayMode(.inline)
            .appBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        seService.confirmEditing(session: session)
                        exerciseService.editingContent = ""
                    } label: {
                        Text(LocalizedStringResource("sessions.action.save", defaultValue: "Save", table: "Sessions"))
                    }
                }
            
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        seService.endEditing()
                        exerciseService.editingContent = ""
                    } label: {
                        Text(LocalizedStringResource("sessions.action.cancel", defaultValue: "Cancel", table: "Sessions"))
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

    func createAndQueueExercise() {
        let exerciseNew = exerciseService.addExercise()
        DispatchQueue.main.async {
            if let exercise = exerciseNew {
                addExerciseEditing(exercise: exercise)
            }
        }
    }
    
    func performSearch() {
        print("searching \(exerciseService.editingContent)")
        searchResults = exerciseService.search(query: exerciseService.editingContent)
    }
}
