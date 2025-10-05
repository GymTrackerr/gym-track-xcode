//
//  SessionExerciseView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-05.
//

import SwiftUI

struct SessionExerciseView : View {
    @EnvironmentObject var setService: SetService
//    @EnvironmentObject var exerciseService: ExerciseService
    
    @Bindable var sessionExercise: SessionExercise
    @State var sessionSet: SessionSet?
    
    var body: some View {
        // show sets in exercise
        List {
            HStack {
                Button {
                    setService.creatingSet = true
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("New Set")
                    }
                }
            }
                
            ForEach(sessionExercise.sets.sorted { $0.order < $1.order }, id: \.id) { sessionSet in
                
                NavigationLink {
                    SingleSetView(sessionSet: sessionSet)
                } label: {
                    HStack {
                        Text("Set #\(sessionSet.order+1)")
                    }
                }
            }
            
        }
        .navigationTitle(Text("Sets"))
        .sheet(isPresented: $setService.creatingSet) {
            NavigationView {
                if let sessionSet {
                    CreateSetView(sessionExercise: sessionExercise, sessionSet: sessionSet)
                }
            }
            .onAppear(perform: createSet)
        }
    }
    
    func createSet() {
        sessionSet = setService.addSet(sessionExercise: sessionExercise)
    }
}

