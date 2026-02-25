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

    @Bindable var sessionEntry: SessionEntry

    @State private var isEditingSets: Bool = false
    @State private var draftNotes: String = ""
    @State private var isDropSet: Bool = false
    @State private var draftUnit: WeightUnit = .lb
    @State private var draftReps: [RepDraft] = [RepDraft()]
    @State private var cardioDurationText: String = ""
    @State private var cardioDistanceText: String = ""
    @State private var cardioPaceText: String = ""
    @State private var cardioDistanceUnit: DistanceUnit = .km

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                timerQuickCard
                detailsQuickCard

                if isEditingSets {
                    editingSetsView
                } else {
                    addSetForm
                    todaysSetsList
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
                Button(isEditingSets ? "Done" : "Edit") {
                    isEditingSets.toggle()
                }
            }
        }
        .onAppear {
            applyLastRepDefaultsIfNeeded()
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
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Duration (sec)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        TextField("", text: $cardioDurationText)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Distance")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        TextField("", text: $cardioDistanceText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                HStack(spacing: 12) {
                    Picker("Unit", selection: $cardioDistanceUnit) {
                        Text("km").tag(DistanceUnit.km)
                        Text("mi").tag(DistanceUnit.mi)
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pace (sec)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        TextField("", text: $cardioPaceText)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
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

    private var todaysSetsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today's Sets")
                .font(.headline)

            ForEach(sessionEntry.sets.sorted { $0.order < $1.order }, id: \.id) { sessionSet in
                VStack(alignment: .leading, spacing: 8) {
                    if sessionEntry.exercise.cardio {
                        HStack(spacing: 12) {
                            setBadge(text: "\(sessionSet.order + 1)")

                            VStack(alignment: .leading, spacing: 4) {
                                Text(cardioSetSummaryText(for: sessionSet))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)

                                if let notes = sessionSet.notes, !notes.isEmpty {
                                    Text(notes)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()
                        }
                    } else if sessionSet.isDropSet {
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
                    } else {
                        HStack(spacing: 12) {
                            setBadge(text: "\(sessionSet.order + 1)")

                            VStack(alignment: .leading, spacing: 4) {
                                Text(setSummaryText(for: sessionSet))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)

                                if let notes = sessionSet.notes, !notes.isEmpty {
                                    Text(notes)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()
                        }
                    }

                    if !sessionEntry.exercise.cardio, sessionSet.isDropSet, let notes = sessionSet.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 40)
                    }
                }
                .padding(12)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
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

                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Duration")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    TextField(
                                        "sec",
                                        text: intTextBinding(for: sessionSet, keyPath: \.durationSeconds)
                                    )
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Distance")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    TextField(
                                        "value",
                                        text: doubleTextBinding(for: sessionSet, keyPath: \.distance)
                                    )
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Unit")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Picker("Distance Unit", selection: distanceUnitBinding(for: sessionSet)) {
                                        Text("km").tag(DistanceUnit.km)
                                        Text("mi").tag(DistanceUnit.mi)
                                    }
                                    .pickerStyle(.segmented)
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Pace")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField(
                                    "sec",
                                    text: intTextBinding(for: sessionSet, keyPath: \.paceSeconds)
                                )
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
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

    private func addSetFromDraft() {
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
        guard let newSet = setService.addSet(sessionEntry: sessionEntry, notes: draftNotes, isDropSet: false) else { return }
        newSet.durationSeconds = Int(cardioDurationText.trimmingCharacters(in: .whitespacesAndNewlines))
        newSet.distance = Double(cardioDistanceText.trimmingCharacters(in: .whitespacesAndNewlines))
        newSet.distanceUnit = cardioDistanceUnit
        newSet.paceSeconds = Int(cardioPaceText.trimmingCharacters(in: .whitespacesAndNewlines))
        setService.saveSetData(sessionSet: newSet)
    }

    private func removeSet(_ sessionSet: SessionSet) {
        setService.deleteSet(sessionEntry: sessionEntry, sessionSet: sessionSet)
    }

    private func deleteRep(sessionSet: SessionSet, rep: SessionRep) {
        setService.deleteRep(sessionSet: sessionSet, rep: rep)
    }

    private func addDropRep(to sessionSet: SessionSet) {
        let lastRep = sessionSet.sessionReps.last
        let unit = lastRep?.weightUnit ?? .lb
        let weight = lastRep?.weight ?? 0
        let reps = lastRep?.count ?? 0
        sessionSet.isDropSet = true
        _ = setService.addRep(sessionSet: sessionSet, weight: weight, reps: reps, unit: unit)
        setService.saveSetData(sessionSet: sessionSet)
    }

    private func applyLastRepDefaultsIfNeeded() {
        guard !sessionEntry.exercise.cardio else { return }
        if let rep = setService.mostRecentRep(for: sessionEntry.exercise) {
            let unit = rep.weightUnit
            draftUnit = unit
            draftReps = [RepDraft(weight: rep.weight, reps: rep.count, unit: unit)]
        }
    }

    private func cardioSetSummaryText(for sessionSet: SessionSet) -> String {
        var parts: [String] = []
        if let duration = sessionSet.durationSeconds {
            parts.append("Duration \(duration)s")
        }
        if let distance = sessionSet.distance {
            parts.append("Distance \(distance.clean) \(sessionSet.distanceUnit.rawValue)")
        }
        if let pace = sessionSet.paceSeconds {
            parts.append("Pace \(pace)s")
        }
        if parts.isEmpty {
            return "Cardio set"
        }
        return parts.joined(separator: " • ")
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

    private func setSummaryText(for sessionSet: SessionSet) -> String {
        if sessionSet.sessionReps.count > 1 {
            return "Drop Set • \(sessionSet.sessionReps.count) reps"
        }

        if let rep = sessionSet.sessionReps.first {
            return "\(rep.weight.clean) \(rep.weightUnit.name)s x \(rep.count) reps"
        }

        return "No reps"
    }

    private func firstRep(for sessionSet: SessionSet) -> SessionRep? {
        if sessionSet.sessionReps.isEmpty {
            return nil
        }

        return sessionSet.sessionReps.first
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
private func dismissKeyboard() {
#if os(iOS)
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
}
