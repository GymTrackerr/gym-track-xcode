//
//  SingleSetView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-05.
//

import SwiftUI

struct SingleSetLabelView: View {
    @EnvironmentObject var setService: SetService
    @Bindable var sessionSet: SessionSet
    
    var body: some View {
        VStack {
            HStack {
                Text(
                    LocalizedStringResource(
                        "sessions.set.label.number",
                        defaultValue: "Set #\(sessionSet.order + 1)",
                        table: "Sessions"
                    )
                )
                Spacer()
            }
            HStack {
                Text(
                    LocalizedStringResource(
                        "sessions.set.label.reps",
                        defaultValue: "Reps: \(setService.getSetRepCount(sessionSet: sessionSet))",
                        table: "Sessions"
                    )
                )
                Spacer()
            }
            HStack {
                Text(
                    LocalizedStringResource(
                        "sessions.set.label.load",
                        defaultValue: "Load: \(setService.getSetWorkload(sessionSet: sessionSet))",
                        table: "Sessions"
                    )
                )
                Spacer()
            }
        }
    }
}

struct CreateSetView: View {
    @EnvironmentObject var setService: SetService
    @Bindable var sessionEntry: SessionEntry
    @Bindable var sessionSet: SessionSet

    var body: some View {
        VStack(spacing: 16) {
            Text(
                LocalizedStringResource(
                    "sessions.set.editTitle",
                    defaultValue: "Edit Set #\(sessionSet.order + 1)",
                    table: "Sessions"
                )
            )
                .font(.headline)
            TextField(text: $setService.create_notes, prompt: Text(LocalizedStringResource("sessions.set.notes.placeholder", defaultValue: "Notes", table: "Sessions"))) {
                Text(LocalizedStringResource("sessions.set.notes.placeholder", defaultValue: "Notes", table: "Sessions"))
            }
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            
            Text(LocalizedStringResource("sessions.set.addReps", defaultValue: "Add Reps", table: "Sessions"))
            ForEach (sessionSet.sessionReps, id: \.id) { rep in
                CreateSingleRepView(sessionSet: sessionSet, sessionRep: rep)
            }

            Spacer()
            Button {
                _ = setService.createBlankRep(sessionSet: sessionSet)
            } label: {
                Label {
                    Text(LocalizedStringResource("sessions.set.addRep", defaultValue: "Add Rep", table: "Sessions"))
                } icon: {
                    Image(systemName: "plus.circle.fill")
                }
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
            .padding(.top, 4)
            
            VStack {
                Button {
                    setService.saveSetData(sessionSet: sessionSet)
                    setService.toggleSetCompletion(sessionSet: sessionSet)
                } label: {
                    Label {
                        Text(LocalizedStringResource("sessions.action.save", defaultValue: "Save", table: "Sessions"))
                    } icon: {
                        Image(systemName: "plus.circle")
                    }
                        .font(.title2)
                        .padding()
                }
            }
            Spacer()
        }
        .screenContentPadding()
        .navigationTitle(Text(LocalizedStringResource("sessions.set.createTitle", defaultValue: "Create New Set", table: "Sessions")))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    setService.completeEditingSet(sessionSet: sessionSet)
                } label: {
                    Text(LocalizedStringResource("sessions.action.done", defaultValue: "Done", table: "Sessions"))
                }
            }
        }
    }
}

struct CreateSingleRepView: View {
    @EnvironmentObject var setService: SetService
    @Bindable var sessionSet: SessionSet
    @Bindable var sessionRep: SessionRep

    var body: some View {
        HStack(spacing: 10) {
            VStack {
                Text(LocalizedStringResource("sessions.set.weight", defaultValue: "Weight", table: "Sessions"))
                TextField(value: $sessionRep.weight, format: .number, prompt: Text(LocalizedStringResource("sessions.set.weight", defaultValue: "Weight", table: "Sessions"))) {
                    Text(LocalizedStringResource("sessions.set.weight", defaultValue: "Weight", table: "Sessions"))
                }
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }

            VStack {
                Text(LocalizedStringResource("sessions.set.reps", defaultValue: "Reps", table: "Sessions"))
                TextField(value: $sessionRep.count, format: .number, prompt: Text(LocalizedStringResource("sessions.set.reps", defaultValue: "Reps", table: "Sessions"))) {
                    Text(LocalizedStringResource("sessions.set.reps", defaultValue: "Reps", table: "Sessions"))
                }
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                
            }
            VStack {
                Text(LocalizedStringResource("sessions.set.weightUnit", defaultValue: "Weight Unit", table: "Sessions"))

                Menu {
                    ForEach (WeightUnit.allCases, id: \.id) { weightUnit in
                        Button(weightUnit.name, action: {
                            $sessionRep.weight_unit.wrappedValue = weightUnit.id
                            setService.saveRepData(sessionRep:sessionRep)
                        })
                    }
                } label: {
                    Label {
                        Text(verbatim: sessionRep.weightUnit.name)
                    } icon: {
                        Image(systemName: "chevron.down")
                    }
                }
            }
        }
        .onChange(of: sessionRep) {
            setService.saveRepData(sessionRep:sessionRep)
        }
    }
}
