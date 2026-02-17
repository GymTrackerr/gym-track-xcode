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
    
    @Bindable var sessionEntry: SessionEntry
    @State var currentSessionSet: SessionSet?
    @State var latestRep: SessionRep?
    
    var body: some View {
        // show sets in exercise
        List {
            Section {
                VStack {
                    Text("Sets for " + sessionEntry.exercise.name)
                }
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
            
            ForEach(sessionEntry.sets.sorted { $0.order < $1.order }, id: \.id) { sessionSet in
                VStack {
                    if (currentSessionSet == sessionSet) && (sessionSet.isCompleted == false) {
                        CreateSetView(sessionEntry: sessionEntry, sessionSet: sessionSet)
                    } else {
                        SingleSetLabelView(sessionSet: sessionSet)
                    }
                }
            }
        }
        .navigationTitle(Text(sessionEntry.exercise.name))
    }
    
    func createSet() {
        if let newSessionSet = setService.addSet(sessionEntry: sessionEntry) {
            currentSessionSet = newSessionSet
            latestRep = setService.createBlankRep(sessionSet: newSessionSet)
            
        }
    }
}
