import SwiftUI

enum RepsInputMode: String, CaseIterable, Identifiable {
    case none = "None"
    case fixed = "Target"
    case range = "Range"

    var id: String { rawValue }
}

struct ProgressionDefaultsFormState {
    var selectedProgressionId: UUID?
    var setsTargetText: String = ""
    var repsMode: RepsInputMode = .none
    var repsTargetText: String = ""
    var repsLowText: String = ""
    var repsHighText: String = ""

    mutating func setValues(
        progressionId: UUID?,
        setsTarget: Int?,
        repsTarget: Int?,
        repsLow: Int?,
        repsHigh: Int?
    ) {
        selectedProgressionId = progressionId
        setsTargetText = setsTarget.map(String.init) ?? ""

        if let repsTarget {
            repsMode = .fixed
            repsTargetText = String(repsTarget)
            repsLowText = ""
            repsHighText = ""
            return
        }

        if repsLow != nil || repsHigh != nil {
            repsMode = .range
            repsTargetText = ""
            repsLowText = repsLow.map(String.init) ?? ""
            repsHighText = repsHigh.map(String.init) ?? ""
            return
        }

        repsMode = .none
        repsTargetText = ""
        repsLowText = ""
        repsHighText = ""
    }

    var parsed: ParsedProgressionDefaultsInput {
        let setsTarget = parseInt(setsTargetText)

        let repsTarget: Int?
        let repsLow: Int?
        let repsHigh: Int?

        switch repsMode {
        case .none:
            repsTarget = nil
            repsLow = nil
            repsHigh = nil
        case .fixed:
            repsTarget = parseInt(repsTargetText)
            repsLow = nil
            repsHigh = nil
        case .range:
            repsTarget = nil
            repsLow = parseInt(repsLowText)
            repsHigh = parseInt(repsHighText)
        }

        return ParsedProgressionDefaultsInput(
            setsTarget: setsTarget,
            repsTarget: repsTarget,
            repsLow: repsLow,
            repsHigh: repsHigh
        )
    }

    private func parseInt(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
    }
}

struct ParsedProgressionDefaultsInput {
    let setsTarget: Int?
    let repsTarget: Int?
    let repsLow: Int?
    let repsHigh: Int?
}

struct ProgressionDefaultsFormSection: View {
    let title: String
    @Binding var formState: ProgressionDefaultsFormState
    let profiles: [ProgressionProfile]

    var body: some View {
        Section(title) {
            Picker("Progression", selection: $formState.selectedProgressionId) {
                Text("None").tag(UUID?.none)
                ForEach(profiles, id: \.id) { profile in
                    Text(profile.name).tag(Optional(profile.id))
                }
            }

            TextField("Sets Target", text: $formState.setsTargetText)
                .keyboardType(.numberPad)

            Picker("Reps Mode", selection: $formState.repsMode) {
                ForEach(RepsInputMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if formState.repsMode == .fixed {
                TextField("Reps Target", text: $formState.repsTargetText)
                    .keyboardType(.numberPad)
            } else if formState.repsMode == .range {
                TextField("Reps Low", text: $formState.repsLowText)
                    .keyboardType(.numberPad)
                TextField("Reps High", text: $formState.repsHighText)
                    .keyboardType(.numberPad)
            }
        }
    }
}
