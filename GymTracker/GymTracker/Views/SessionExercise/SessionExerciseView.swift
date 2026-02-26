//
//  SessionExerciseView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-05.
//

import SwiftUI

struct SessionExerciseView: View {
    @EnvironmentObject var setService: SetService
    @EnvironmentObject var timerService: TimerService
    @EnvironmentObject var exerciseService: ExerciseService

    @Bindable var sessionEntry: SessionEntry
    let navigationContext: SessionNavigationContext

    @State private var isEditingSets: Bool = false
    @State private var isUnlockedForEditing: Bool = false
    @State private var draftNotes: String = ""
    @State private var isDropSet: Bool = false
    @State private var draftUnit: WeightUnit = .lb
    @State private var draftReps: [RepDraft] = [RepDraft()]
    @State private var cardioDurationSeconds: Int = 0
    @State private var cardioDistanceText: String = ""
    @State private var cardioPaceText: String = ""
    @State private var cardioDistanceUnit: DistanceUnit = .km
    @State private var cardioManualPace: Bool = false
    @State private var setToMove: SessionSet? = nil
    @State private var showMoveSetPicker: Bool = false
    @State private var moveSetErrorMessage: String? = nil

    init(sessionEntry: SessionEntry, navigationContext: SessionNavigationContext? = nil) {
        self.sessionEntry = sessionEntry
        self.navigationContext = navigationContext ?? SessionNavigationContext.forSession(sessionEntry.session)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                contextBadge
                timerQuickCard
                if !navigationContext.isFromExerciseHistory {
                    detailsQuickCard
                }

                if isEditingSets {
                    editingSetsView
                } else {
                    if canEditSession {
                        addSetForm
                    } else {
                        lockedEditingNotice
                    }
                    todaysSetsList
                }

                if navigationContext.isFromExerciseHistory {
                    openFullSessionButton
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .navigationTitle(sessionEntry.exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if canEditSession {
                    Button(isEditingSets ? "Done" : "Edit") {
                        isEditingSets.toggle()
                    }
                } else if navigationContext.allowsUnlock {
                    Button("Unlock") {
                        isUnlockedForEditing = true
                    }
                }
            }
        }
        .onAppear {
            applyLastDefaultsIfNeeded()
        }
        .sheet(isPresented: $showMoveSetPicker, onDismiss: {
            setToMove = nil
        }) {
            if let setToMove {
                MoveSetExercisePickerView(
                    sourceExercise: sessionEntry.exercise,
                    sessionDate: sessionEntry.session.timestamp,
                    setCount: 1,
                    exercises: moveTargetExercises,
                    onConfirm: { targetExercise in
                        moveSet(setToMove, to: targetExercise)
                    }
                )
            }
        }
        .alert("Unable to move set", isPresented: Binding(
            get: { moveSetErrorMessage != nil },
            set: { if !$0 { moveSetErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { moveSetErrorMessage = nil }
        } message: {
            Text(moveSetErrorMessage ?? "Unknown error")
        }
    }

    private var timerQuickCard: some View {
        NavigationLink {
            TimerView().appBackground()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 2) {
                    Text(timerButtonTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    if timerService.timer != nil {
                        Text("Time Remaining")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("View timer")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var contextBadge: some View {
        HStack {
            Text(navigationContext.statusBadgeText)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.gray.opacity(0.12))
                .clipShape(Capsule())
            Spacer()
        }
    }

    private var detailsQuickCard: some View {
        NavigationLink {
            SingleExerciseView(exercise: sessionEntry.exercise).appBackground()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "info.circle")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Details")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("View exercise info")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var addSetForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Current Set")
                .font(.caption)
                .foregroundColor(.secondary)

            if sessionEntry.exercise.cardio {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Time (HH:MM:SS)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        DurationWheelPicker(totalSeconds: $cardioDurationSeconds)
                        Text(SetDisplayFormatter.formatClockDuration(cardioDurationSeconds))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Distance")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        HStack(spacing: 10) {
                            TextField("", text: $cardioDistanceText)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)

                            Picker("Unit", selection: $cardioDistanceUnit) {
                                Text("km").tag(DistanceUnit.km)
                                Text("mi").tag(DistanceUnit.mi)
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 130)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Manual Pace", isOn: $cardioManualPace)
                        if cardioManualPace {
                            HStack(spacing: 8) {
                                Text("Pace")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                TextField("", text: $cardioPaceText)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                                Text("/\(cardioDistanceUnit.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if let estimated = calculateEstimatedPace(
                            distance: Double(cardioDistanceText.trimmingCharacters(in: .whitespacesAndNewlines)),
                            durationSeconds: cardioDurationSeconds > 0 ? cardioDurationSeconds : nil,
                            distanceUnit: cardioDistanceUnit
                        ) {
                            Text("Estimated Pace \(estimated)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Estimated Pace --")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Weight")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        TextField("", value: $draftReps[0].weight, formatter: weightFormatter)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reps")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        TextField("", value: $draftReps[0].reps, formatter: repsFormatter)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Picker("Unit", selection: $draftUnit) {
                    ForEach(WeightUnit.allCases) { unit in
                        Text(unit.name).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: draftUnit) { _, newValue in
                    updateDraftUnits(to: newValue)
                }
            }

            Button {
                addSetFromDraft()
                dismissKeyboard()
                startTimerIfNeeded()
            } label: {
                Label("Add Set", systemImage: "plus")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)

            if !sessionEntry.exercise.cardio {
                Toggle("Drop Set", isOn: $isDropSet)
                    .onChange(of: isDropSet) { _, newValue in
                        if !newValue {
                            trimToSingleRep()
                        } else if draftReps.isEmpty {
                            draftReps = [RepDraft(unit: draftUnit)]
                        }
                    }

                if isDropSet {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Drop Set Reps")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        ForEach(draftReps.indices, id: \.self) { index in
                            HStack(spacing: 12) {
                                TextField("Weight", value: $draftReps[index].weight, formatter: weightFormatter)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Reps", value: $draftReps[index].reps, formatter: repsFormatter)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                                if draftReps.count > 1 {
                                    Button(role: .destructive) {
                                        draftReps.remove(at: index)
                                    } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                }
                            }
                        }

                        Button {
                            let previousWeight = draftReps.last?.weight ?? 0
                            let previousReps = draftReps.last?.reps ?? 0
                            draftReps.append(RepDraft(weight: previousWeight, reps: previousReps, unit: draftUnit))
                        } label: {
                            Label("Add Rep", systemImage: "plus.circle")
                                .font(.subheadline)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Notes")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                TextEditor(text: $draftNotes)
                    .frame(minHeight: 90)
                    .padding(8)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

        }
        .padding(12)
        .background(Color.gray.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var lockedEditingNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Read-only")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text("This session is not active. Unlock to add or edit sets.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.gray.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var todaysSetsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today's Sets")
                .font(.headline)

            let exerciseKind = sessionEntry.exercise.setDisplayKind
            let meaningfulSets = sessionEntry.sets
                .sorted { $0.order < $1.order }
                .filter { SetDisplayFormatter.isMeaningfulSet($0, exerciseKind: exerciseKind) }

            ForEach(meaningfulSets, id: \.id) { sessionSet in
                let summary = SetDisplayFormatter.formatSetSummary(
                    sessionSet,
                    exerciseKind: exerciseKind
                )
                if !sessionEntry.exercise.cardio && sessionSet.isDropSet {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(sessionSet.sessionReps.indices, id: \.self) { index in
                            let rep = sessionSet.sessionReps[index]
                            HStack(spacing: 12) {
                                setBadge(text: badgeText(for: sessionSet, repIndex: index))

                                Text("\(rep.weight.clean) \(rep.weightUnit.name)s x \(rep.count) reps")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)

                                Spacer()
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard canEditSession else { return }
                        copySetIntoCurrentDraft(sessionSet)
                    }
                    .contextMenu {
                        if canEditSession {
                            Button("Copy into Current") {
                                copySetIntoCurrentDraft(sessionSet)
                            }
                            Button("Duplicate Set") {
                                duplicateSet(sessionSet)
                            }
                            Button("Transfer Set") {
                                startMoveSetFlow(for: sessionSet)
                            }
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        setBadge(text: "\(sessionSet.order + 1)")

                        VStack(alignment: .leading, spacing: 6) {
                            Text(summary.primaryText)
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            if let secondary = summary.secondaryText, !secondary.isEmpty {
                                Text(secondary)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if !summary.chips.isEmpty {
                                HStack(spacing: 6) {
                                    ForEach(summary.chips, id: \.self) { chip in
                                        Text(chip)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.gray.opacity(0.14))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }

                        Spacer()
                    }
                    .padding(12)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard canEditSession else { return }
                        copySetIntoCurrentDraft(sessionSet)
                    }
                    .contextMenu {
                        if canEditSession {
                            Button("Copy into current") {
                                copySetIntoCurrentDraft(sessionSet)
                            }
                            Button("Duplicate set") {
                                duplicateSet(sessionSet)
                            }
                            Button("Transfer set...") {
                                startMoveSetFlow(for: sessionSet)
                            }
                        }
                    }
                }
            }
        }
    }

    private var editingSetsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Sets")
                .font(.headline)

            ForEach(sessionEntry.sets.sorted { $0.order < $1.order }, id: \.id) { sessionSet in
                VStack(alignment: .leading, spacing: 8) {
                    if sessionEntry.exercise.cardio {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                Image(systemName: "line.3.horizontal")
                                    .foregroundColor(.secondary)
                                setBadge(text: "\(sessionSet.order + 1)")
                                Text("Cardio Set")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Spacer()
                                Button(role: .destructive) {
                                    removeSet(sessionSet)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Duration")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    DurationWheelPicker(totalSeconds: durationSecondsBinding(for: sessionSet))
                                    Text(SetDisplayFormatter.formatClockDuration(sessionSet.durationSeconds ?? 0))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Distance")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    HStack(spacing: 10) {
                                        TextField(
                                            "value",
                                            text: doubleTextBinding(for: sessionSet, keyPath: \.distance)
                                        )
                                        .keyboardType(.decimalPad)
                                        .textFieldStyle(.roundedBorder)

                                        Picker("Distance Unit", selection: distanceUnitBinding(for: sessionSet)) {
                                            Text("km").tag(DistanceUnit.km)
                                            Text("mi").tag(DistanceUnit.mi)
                                        }
                                        .pickerStyle(.segmented)
                                        .frame(maxWidth: 130)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Toggle("Manual Pace", isOn: manualPaceBinding(for: sessionSet))
                                        .font(.caption)
                                    if (sessionSet.paceSeconds ?? 0) > 0 {
                                        HStack(spacing: 8) {
                                            Text("Pace")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            TextField(
                                                "sec",
                                                text: intTextBinding(for: sessionSet, keyPath: \.paceSeconds)
                                            )
                                            .keyboardType(.numberPad)
                                            .textFieldStyle(.roundedBorder)
                                            Text("/\(sessionSet.distanceUnit.rawValue)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    } else if let estimated = calculateEstimatedPace(
                                        distance: sessionSet.distance,
                                        durationSeconds: sessionSet.durationSeconds,
                                        distanceUnit: sessionSet.distanceUnit
                                    ) {
                                        Text("Estimated Pace \(estimated)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("Estimated Pace --")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } else {
                        if sessionSet.sessionReps.isEmpty {
                            HStack(spacing: 12) {
                                Image(systemName: "line.3.horizontal")
                                    .foregroundColor(.secondary)

                                setBadge(text: "\(sessionSet.order + 1)")

                                if !sessionSet.isDropSet {
                                    Button {
                                        addDropRep(to: sessionSet)
                                    } label: {
                                        Image(systemName: "chevron.down.2")
                                    }
                                    .buttonStyle(.borderless)
                                }

                                Spacer()

                                Button(role: .destructive) {
                                    removeSet(sessionSet)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        } else {
                            ForEach(sessionSet.sessionReps.indices, id: \.self) { index in
                                let rep = sessionSet.sessionReps[index]
                                HStack(spacing: 12) {
                                    if index == 0 {
                                        Image(systemName: "line.3.horizontal")
                                            .foregroundColor(.secondary)
                                    } else {
                                        Color.clear
                                            .frame(width: 18, height: 18)
                                    }

                                    setBadge(text: badgeText(for: sessionSet, repIndex: index))

                                    TextField("Weight", value: binding(for: rep).weight, format: .number)
                                        .keyboardType(.decimalPad)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 70)

                                    Menu {
                                        ForEach(WeightUnit.allCases) { unit in
                                            Button(unit.name) {
                                                rep.weight_unit = unit.rawValue
                                                setService.saveRepData(sessionRep: rep)
                                            }
                                        }
                                    } label: {
                                        Text("\(rep.weightUnit.name)s x")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    TextField("Reps", value: binding(for: rep).count, format: .number)
                                        .keyboardType(.numberPad)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 60)

                                    Spacer()

                                    HStack(spacing: 8) {
                                        if index == 0 {
                                            Button(role: .destructive) {
                                                removeSet(sessionSet)
                                            } label: {
                                                Image(systemName: "trash")
                                            }
                                        }

                                        if sessionSet.isDropSet {
                                            if index == sessionSet.sessionReps.indices.last {
                                                Button {
                                                    addDropRep(to: sessionSet)
                                                } label: {
                                                    Image(systemName: "plus.circle")
                                                }
                                            }

                                            if sessionSet.sessionReps.count > 1 {
                                                Button(role: .destructive) {
                                                    deleteRep(sessionSet: sessionSet, rep: rep)
                                                } label: {
                                                    Image(systemName: "minus.circle")
                                                }
                                            }
                                        } else if index == 0 {
                                            Button {
                                                addDropRep(to: sessionSet)
                                            } label: {
                                                Image(systemName: "chevron.down.2")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(12)
                .background(Color.gray.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var timerButtonTitle: String {
        if timerService.timer != nil {
            return "Timer \(timerService.formatted)"
        }

        return "Timer"
    }

    private var canEditSession: Bool {
        navigationContext.isEditableByDefault || isUnlockedForEditing
    }

    private var openFullSessionButton: some View {
        NavigationLink {
            SingleSessionView(
                session: sessionEntry.session,
                navigationContext: SessionNavigationContext.forSession(sessionEntry.session)
            )
            .appBackground()
        } label: {
            HStack {
                Text("Open full session")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var weightFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        formatter.zeroSymbol = ""
        return formatter
    }

    private var repsFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.maximumFractionDigits = 0
        formatter.zeroSymbol = ""
        return formatter
    }

    private func startTimerIfNeeded() {
        if timerService.timer == nil {
            timerService.start()
        }
    }

    private var moveTargetExercises: [Exercise] {
        let sessionExercises = sessionEntry.session.sessionEntries.map(\.exercise)
        return sessionExercises
            .filter { $0.id != sessionEntry.exercise.id && $0.isArchived == false }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func startMoveSetFlow(for sessionSet: SessionSet) {
        setToMove = sessionSet
        showMoveSetPicker = true
    }

    private func duplicateSet(_ sessionSet: SessionSet) {
        guard canEditSession else { return }
        _ = setService.duplicateSet(sessionSet)
    }

    private func moveSet(_ sessionSet: SessionSet, to targetExercise: Exercise) {
        do {
            try setService.moveSet(sessionSet, to: targetExercise)
            showMoveSetPicker = false
            setToMove = nil
        } catch {
            moveSetErrorMessage = error.localizedDescription
        }
    }

    private func badgeText(for sessionSet: SessionSet, repIndex: Int) -> String {
        if sessionSet.isDropSet {
            return "\(sessionSet.order + 1).\(repIndex + 1)"
        }

        return "\(sessionSet.order + 1)"
    }

    @ViewBuilder
    private func setBadge(text: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(0.12))
            Text(text)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .frame(width: 36, height: 28)
    }

    private func updateDraftUnits(to unit: WeightUnit) {
        for index in draftReps.indices {
            draftReps[index].unit = unit
        }
    }

    private func trimToSingleRep() {
        if let first = draftReps.first {
            draftReps = [first]
        } else {
            draftReps = [RepDraft(unit: draftUnit)]
        }
    }

    private func copySetIntoCurrentDraft(_ sourceSet: SessionSet) {
        if sessionEntry.exercise.cardio {
            cardioDurationSeconds = max(sourceSet.durationSeconds ?? 0, 0)
            cardioDistanceText = sourceSet.distance?.clean ?? ""
            cardioDistanceUnit = sourceSet.distanceUnit
            if let pace = sourceSet.paceSeconds, pace > 0 {
                cardioManualPace = true
                cardioPaceText = String(pace)
            } else {
                cardioManualPace = false
                cardioPaceText = ""
            }
            draftNotes = sourceSet.notes ?? ""
            return
        }

        guard !sourceSet.sessionReps.isEmpty else { return }
        let copiedReps = sourceSet.sessionReps.map {
            RepDraft(weight: $0.weight, reps: $0.count, unit: $0.weightUnit)
        }
        if let firstUnit = copiedReps.first?.unit {
            draftUnit = firstUnit
        }
        draftReps = copiedReps
        isDropSet = sourceSet.isDropSet && copiedReps.count > 1
        if !isDropSet {
            trimToSingleRep()
        }
        draftNotes = sourceSet.notes ?? ""
    }

    private func addSetFromDraft() {
        guard canEditSession else { return }
        if sessionEntry.exercise.cardio {
            addCardioSetFromDraft()
            return
        }

        let useDropSet = isDropSet && draftReps.count > 1
        guard let newSet = setService.addSet(sessionEntry: sessionEntry, notes: draftNotes, isDropSet: useDropSet) else { return }

        let repsToCreate = useDropSet ? draftReps : Array(draftReps.prefix(1))
        for draft in repsToCreate {
            _ = setService.addRep(sessionSet: newSet, weight: draft.weight, reps: draft.reps, unit: draft.unit)
        }

    }

    private func addCardioSetFromDraft() {
        guard canEditSession else { return }
        guard let newSet = setService.addSet(sessionEntry: sessionEntry, notes: draftNotes, isDropSet: false) else { return }
        newSet.durationSeconds = cardioDurationSeconds > 0 ? cardioDurationSeconds : nil
        newSet.distance = Double(cardioDistanceText.trimmingCharacters(in: .whitespacesAndNewlines))
        newSet.distanceUnit = cardioDistanceUnit
        if cardioManualPace {
            newSet.paceSeconds = Int(cardioPaceText.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            newSet.paceSeconds = nil
        }
        setService.saveSetData(sessionSet: newSet)
    }

    private func removeSet(_ sessionSet: SessionSet) {
        guard canEditSession else { return }
        setService.deleteSet(sessionEntry: sessionEntry, sessionSet: sessionSet)
    }

    private func deleteRep(sessionSet: SessionSet, rep: SessionRep) {
        guard canEditSession else { return }
        setService.deleteRep(sessionSet: sessionSet, rep: rep)
    }

    private func addDropRep(to sessionSet: SessionSet) {
        guard canEditSession else { return }
        let lastRep = sessionSet.sessionReps.last
        let unit = lastRep?.weightUnit ?? .lb
        let weight = lastRep?.weight ?? 0
        let reps = lastRep?.count ?? 0
        sessionSet.isDropSet = true
        _ = setService.addRep(sessionSet: sessionSet, weight: weight, reps: reps, unit: unit)
        setService.saveSetData(sessionSet: sessionSet)
    }

    private func applyLastDefaultsIfNeeded() {
        if sessionEntry.exercise.cardio {
            let hasDraft = cardioDurationSeconds > 0 ||
                !cardioDistanceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                !cardioPaceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard !hasDraft else { return }
            let recentSet = sessionEntry.sets
                .sorted { $0.timestamp > $1.timestamp }
                .first {
                    ($0.durationSeconds ?? 0) > 0 ||
                    ($0.distance ?? 0) > 0 ||
                    ($0.paceSeconds ?? 0) > 0
                } ?? setService.mostRecentCardioSet(for: sessionEntry.exercise)
            guard let recentSet else { return }

            cardioDurationSeconds = recentSet.durationSeconds ?? 0
            cardioDistanceText = recentSet.distance?.clean ?? ""
            cardioDistanceUnit = recentSet.distanceUnit
            if let pace = recentSet.paceSeconds, pace > 0 {
                cardioManualPace = true
                cardioPaceText = String(pace)
            } else {
                cardioManualPace = false
                cardioPaceText = ""
            }
            return
        }

        if let rep = setService.mostRecentRep(for: sessionEntry.exercise) {
            let unit = rep.weightUnit
            draftUnit = unit
            draftReps = [RepDraft(weight: rep.weight, reps: rep.count, unit: unit)]
        }
    }

    private func intTextBinding(
        for sessionSet: SessionSet,
        keyPath: ReferenceWritableKeyPath<SessionSet, Int?>
    ) -> Binding<String> {
        Binding(
            get: {
                guard let value = sessionSet[keyPath: keyPath] else { return "" }
                return String(value)
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                sessionSet[keyPath: keyPath] = Int(trimmed)
                setService.saveSetData(sessionSet: sessionSet)
            }
        )
    }

    private func doubleTextBinding(
        for sessionSet: SessionSet,
        keyPath: ReferenceWritableKeyPath<SessionSet, Double?>
    ) -> Binding<String> {
        Binding(
            get: {
                guard let value = sessionSet[keyPath: keyPath] else { return "" }
                return value.clean
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                sessionSet[keyPath: keyPath] = Double(trimmed)
                setService.saveSetData(sessionSet: sessionSet)
            }
        )
    }

    private func distanceUnitBinding(for sessionSet: SessionSet) -> Binding<DistanceUnit> {
        Binding(
            get: { sessionSet.distanceUnit },
            set: { newValue in
                sessionSet.distanceUnit = newValue
                setService.saveSetData(sessionSet: sessionSet)
            }
        )
    }

    private func durationSecondsBinding(for sessionSet: SessionSet) -> Binding<Int> {
        Binding(
            get: { max(sessionSet.durationSeconds ?? 0, 0) },
            set: { newValue in
                let clamped = max(newValue, 0)
                sessionSet.durationSeconds = clamped > 0 ? clamped : nil
                setService.saveSetData(sessionSet: sessionSet)
            }
        )
    }

    private func manualPaceBinding(for sessionSet: SessionSet) -> Binding<Bool> {
        Binding(
            get: { (sessionSet.paceSeconds ?? 0) > 0 },
            set: { newValue in
                if !newValue {
                    sessionSet.paceSeconds = nil
                }
                setService.saveSetData(sessionSet: sessionSet)
            }
        )
    }

    private func calculateEstimatedPace(
        distance: Double?,
        durationSeconds: Int?,
        distanceUnit: DistanceUnit
    ) -> String? {
        let resolvedPace = SetDisplayFormatter.resolvePaceSeconds(
            explicitPaceSeconds: nil,
            durationSeconds: durationSeconds,
            distance: distance
        )
        return SetDisplayFormatter.formatPace(
            secondsPerSourceUnit: resolvedPace,
            sourceUnit: distanceUnit,
            preferredDistanceUnit: distanceUnit
        )
    }

    private func binding(for rep: SessionRep) -> (weight: Binding<Double>, count: Binding<Int>) {
        (
            weight: Binding(
                get: { rep.weight },
                set: { newValue in
                    rep.weight = newValue
                    setService.saveRepData(sessionRep: rep)
                }
            ),
            count: Binding(
                get: { rep.count },
                set: { newValue in
                    rep.count = newValue
                    setService.saveRepData(sessionRep: rep)
                }
            )
        )
    }
}

private struct MoveSetExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss

    let sourceExercise: Exercise
    let sessionDate: Date
    let setCount: Int
    let exercises: [Exercise]
    let onConfirm: (Exercise) -> Void

    @State private var searchText: String = ""
    @State private var selectedExerciseId: UUID? = nil

    private var selectedExercise: Exercise? {
        guard let selectedExerciseId else { return nil }
        return exercises.first { $0.id == selectedExerciseId }
    }

    private var filteredExercises: [Exercise] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return exercises }
        return exercises.filter { exercise in
            if exercise.name.localizedCaseInsensitiveContains(query) {
                return true
            }
            return (exercise.aliases ?? []).contains { alias in
                alias.localizedCaseInsensitiveContains(query)
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Confirm Transfer") {
                    detailRow(title: "From", value: sourceExercise.name)
                    detailRow(title: "To", value: selectedExercise?.name ?? "Select target")
                    detailRow(
                        title: "Session",
                        value: sessionDate.formatted(date: .abbreviated, time: .shortened)
                    )
                    detailRow(title: "Sets", value: "\(setCount)")
                }

                Section("Target Exercise") {
                    ForEach(filteredExercises, id: \.id) { exercise in
                        Button {
                            selectedExerciseId = exercise.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(exercise.name)
                                        .foregroundStyle(.primary)
                                    if let aliases = exercise.aliases, !aliases.isEmpty {
                                        Text(aliases.joined(separator: ", "))
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                if selectedExerciseId == exercise.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Transfer Set")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search exercise")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Transfer") {
                        guard let selectedExercise else { return }
                        onConfirm(selectedExercise)
                        dismiss()
                    }
                    .disabled(selectedExercise == nil)
                }
            }
        }
    }

    @ViewBuilder
    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct RepDraft: Identifiable {
    let id = UUID()
    var weight: Double = 0
    var reps: Int = 0
    var unit: WeightUnit = .lb

    init(weight: Double = 0, reps: Int = 0, unit: WeightUnit = .lb) {
        self.weight = weight
        self.reps = reps
        self.unit = unit
    }
}

private extension Double {
    var clean: String {
        if self == floor(self) {
            return String(format: "%.0f", self)
        }
        return String(format: "%.1f", self)
    }
}

private struct DurationWheelPicker: View {
    @Binding var totalSeconds: Int

    private var hoursBinding: Binding<Int> {
        Binding(
            get: { totalSeconds / 3600 },
            set: { newValue in
                let clamped = max(0, min(newValue, 23))
                totalSeconds = (clamped * 3600) + (minutes * 60) + seconds
            }
        )
    }

    private var minutesBinding: Binding<Int> {
        Binding(
            get: { minutes },
            set: { newValue in
                let clamped = max(0, min(newValue, 59))
                totalSeconds = (hours * 3600) + (clamped * 60) + seconds
            }
        )
    }

    private var secondsBinding: Binding<Int> {
        Binding(
            get: { seconds },
            set: { newValue in
                let clamped = max(0, min(newValue, 59))
                totalSeconds = (hours * 3600) + (minutes * 60) + clamped
            }
        )
    }

    private var hours: Int { max(totalSeconds, 0) / 3600 }
    private var minutes: Int { (max(totalSeconds, 0) % 3600) / 60 }
    private var seconds: Int { max(totalSeconds, 0) % 60 }

    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 2) {
                Picker("Hours", selection: hoursBinding) {
                    ForEach(0..<24, id: \.self) { value in
                        Text(String(format: "%02d", value)).tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 66, height: 88)
                .clipped()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                Text("HH")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(":")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 2) {
                Picker("Minutes", selection: minutesBinding) {
                    ForEach(0..<60, id: \.self) { value in
                        Text(String(format: "%02d", value)).tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 66, height: 88)
                .clipped()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                Text("MM")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(":")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 2) {
                Picker("Seconds", selection: secondsBinding) {
                    ForEach(0..<60, id: \.self) { value in
                        Text(String(format: "%02d", value)).tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 66, height: 88)
                .clipped()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                Text("SS")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 112)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
private func dismissKeyboard() {
#if os(iOS)
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
}
