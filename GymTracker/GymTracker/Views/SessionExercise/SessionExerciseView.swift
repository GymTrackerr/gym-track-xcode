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
    @State var currentSessionSet: SessionSet?
    @State var latestRep: SessionRep?
    
    var body: some View {
        // show sets in exercise
        List {
            Section {
                HStack {
                    Button {
                        setService.creatingSet = true
                        createSet()
                        
                    } label: {
                        HStack {
                            Image(systemName: "plus")
                            Text("New Set")
                        }
                    }
                }
            }
            
            ForEach(sessionExercise.sets.sorted { $0.order < $1.order }, id: \.id) { sessionSet in
                VStack {
                    if (currentSessionSet == sessionSet) && (sessionSet.isCompleted == false) {
                        CreateSetView(sessionExercise: sessionExercise, sessionSet: sessionSet)
                    } else {
                        SingleSetLabelView(sessionSet: sessionSet)
                    }
                }
            }
        }
        .navigationTitle(Text("Sets"))
    }
    
    func createSet() {
        if let newSessionSet = setService.addSet(sessionExercise: sessionExercise) {
            currentSessionSet = newSessionSet
            latestRep = setService.createBlankRep(sessionSet: newSessionSet)
            
        }
    }
}

