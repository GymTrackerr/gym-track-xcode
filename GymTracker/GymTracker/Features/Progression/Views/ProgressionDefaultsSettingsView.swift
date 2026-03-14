import SwiftUI

enum RepsInputMode: String, CaseIterable, Identifiable {
    case none = "None"
    case fixed = "Target"
    case range = "Range"

    var id: String { rawValue }
}

struct ProgressionDefaultsSettingsView: View {
    @EnvironmentObject var progressionDefaultsService: ProgressionDefaultsService

    @State private var selectedProgressionId: UUID?
    @State private var setsTargetText: String = ""
    @State private var repsMode: RepsInputMode = .none
    @State private var repsTargetText: String = ""
    @State private var repsLowText: String = ""
    @State private var repsHighText: String = ""

    private var profiles: [ProgressionProfile] {
        progressionDefaultsService.availableProfiles()
    }

    var body: some View {
        Form {
            Section("Global Default") {
                Picker("Progression", selection: $selectedProgressionId) {
                    Text("None").tag(UUID?.none)
                    ForEach(profiles, id: \.id) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }

                TextField("Sets Target", text: $setsTargetText)
                    .keyboardType(.numberPad)

                Picker("Reps Mode", selection: $repsMode) {
                    ForEach(RepsInputMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if repsMode == .fixed {
                    TextField("Reps Target", text: $repsTargetText)
                        .keyboardType(.numberPad)
                } else if repsMode == .range {
                    TextField("Reps Low", text: $repsLowText)
                        .keyboardType(.numberPad)
                    TextField("Reps High", text: $repsHighText)
                        .keyboardType(.numberPad)
                }
            }

            Section {
                Button("Save Default") {
                    save()
                }
                Button("Clear Default", role: .destructive) {
                    clear()
                }
            }
        }
        .navigationTitle("Progression Defaults")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadFromModel()
        }
    }

    private func loadFromModel() {
        guard let model = progressionDefaultsService.currentUserDefault() else {
            selectedProgressionId = nil
            setsTargetText = ""
            repsMode = .none
            repsTargetText = ""
            repsLowText = ""
            repsHighText = ""
            return
        }

        selectedProgressionId = model.progression?.id
        setsTargetText = model.setsTarget.map(String.init) ?? ""
        if let repsTarget = model.repsTarget {
            repsMode = .fixed
            repsTargetText = String(repsTarget)
            repsLowText = ""
            repsHighText = ""
        } else if model.repsLow != nil || model.repsHigh != nil {
            repsMode = .range
            repsTargetText = ""
            repsLowText = model.repsLow.map(String.init) ?? ""
            repsHighText = model.repsHigh.map(String.init) ?? ""
        } else {
            repsMode = .none
            repsTargetText = ""
            repsLowText = ""
            repsHighText = ""
        }
    }

    private func save() {
        let progression = profiles.first(where: { $0.id == selectedProgressionId })
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

        _ = progressionDefaultsService.upsertUserDefault(
            progression: progression,
            setsTarget: setsTarget,
            repsTarget: repsTarget,
            repsLow: repsLow,
            repsHigh: repsHigh
        )
        loadFromModel()
    }

    private func clear() {
        _ = progressionDefaultsService.removeUserDefault()
        loadFromModel()
    }

    private func parseInt(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
    }
}
