//
//  SingleSetView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-05.
//

import SwiftUI

struct SingleSetView : View {
    @Bindable var sessionSet: SessionSet
    
    var body: some View {
        VStack {
            Text("Exercise: \(sessionSet.sessionExercise.exercise.name)")
            Text("Set #\(sessionSet.order+1)")
            Text("Notes: \(sessionSet.notes ?? "")")
        }
    }
}

struct CreateSetView: View {
    @EnvironmentObject var setService: SetService
    @Bindable var sessionExercise: SessionExercise
    @Bindable var sessionSet: SessionSet
//    @Binding var openedSet: Session? = nil

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Set")
                .font(.headline)
            TextField("Notes", text: $setService.create_notes)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            
            /* add reps*/
            Text("Add Reps")
            ForEach (setService.createReps, id: \.id) { rep in
                CreateSingleRepView(sessionSet: sessionSet, sessionRep: rep)
            }

            Spacer()
            Button {
                let newRep = SessionRep(
                    sessionSet: sessionSet,
                    weight: 0,
                    weight_unit: WeightUnit.lb,
                    count: 0
                )
                setService.createReps.append(newRep)
            } label: {
                Label("Add Rep", systemImage: "plus.circle.fill")
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
            .padding(.top, 4)
        Button {
// openedSession = /*sessionService*/.addSession()
            } label: {
                Label("Save", systemImage: "plus.circle")
                    .font(.title2)
                    .padding()
            }
            Spacer()
        }
        .padding()
        .navigationTitle("Create New Set")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    setService.completeEditingSet(sessionSet: sessionSet)
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
            TextField("Weight", value: $sessionRep.weight, format: .number)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)

            TextField("Reps", value: $sessionRep.count, format: .number)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)

            Menu {
                ForEach (WeightUnit.allCases, id: \.id) { weightUnit in
                    Button(weightUnit.name, action: { $sessionRep.weight_unit.wrappedValue = weightUnit.id })
                }
            } label: {
                Label("Weight Type: \(sessionRep.weightUnit.name)", systemImage: "chevron.down")
            }
//            Picker("Unit", selection: $sessionRep.weight_unit) {
//                Text("kg").tag(0)
//                Text("lb").tag(1)
//            }
//            .pickerStyle(.menu)
//            .frame(width: 80)

            Button(role: .destructive) {
                if let index = setService.createReps.firstIndex(where: { $0.id == sessionRep.id }) {
                    setService.createReps.remove(at: index)
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.red)
            }
        }
    }
}
