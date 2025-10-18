//
//  SingleSetView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-05.
//

import SwiftUI

// TODO: make sets moveable, editable, deletable
// must also add ability to add drop sets
// and for different types of sets - running, etc
// sessionExercise? can hold unit weight rather than reps
// have default unit weight from user

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
struct SingleSetLabelView: View {
    @EnvironmentObject var setService: SetService
    @Bindable var sessionSet: SessionSet
    
    var body: some View {
        VStack {
            HStack {
                Text("Set #\(sessionSet.order+1)")
                Spacer()
            }
            HStack {
                Text("Reps: \(setService.getSetRepCount(sessionSet: sessionSet))")
                Spacer()
            }
            HStack {
                Text("Load: \(setService.getSetWorkload(sessionSet: sessionSet))")
                Spacer()
            }
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
            Text("Edit Set #\(sessionSet.order+1)")
                .font(.headline)
            TextField("Notes", text: $setService.create_notes)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            
            /* add reps*/
            Text("Add Reps")
            ForEach (sessionSet.sessionReps, id: \.id) { rep in
                CreateSingleRepView(sessionSet: sessionSet, sessionRep: rep)
            }

            Spacer()
            Button {
                _ = setService.createBlankRep(sessionSet: sessionSet)
            } label: {
                Label("Add Rep", systemImage: "plus.circle.fill")
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
            .padding(.top, 4)
            
            VStack {
                Button {
                    setService.saveSetData(sessionSet: sessionSet)
                    setService.toggleSetCompletion(sessionSet: sessionSet)
                } label: {
                    Label("Save", systemImage: "plus.circle")
                        .font(.title2)
                        .padding()
                }
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
            VStack {
                Text("Weight")
                TextField("Weight", value: $sessionRep.weight, format: .number)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }

            VStack {
                Text("Reps")
                TextField("Reps", value: $sessionRep.count, format: .number)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                
            }
            VStack {
                Text("Weight Unit")

                Menu {
                    ForEach (WeightUnit.allCases, id: \.id) { weightUnit in
                        Button(weightUnit.name, action: {
                            $sessionRep.weight_unit.wrappedValue = weightUnit.id
                            setService.saveRepData(sessionRep:sessionRep)
                        })
                    }
                } label: {
                    Label("\(sessionRep.weightUnit.name)", systemImage: "chevron.down")
                }
            }

            /*
            Button(role: .destructive) {
                if let index = sessionSet.sessionReps.firstIndex(where: { $0.id == sessionRep.id }) {
                    setService.createReps.remove(at: index)
                    setService.saveRepData(sessionRep:sessionRep)
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.red)
            }*/
        }
        .onChange(of: sessionRep) {
            print("changed session rep")
            setService.saveRepData(sessionRep:sessionRep)
        }
    }
}
