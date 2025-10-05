//
//  SetService.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-05.
//

import SwiftUI
import SwiftData
import Combine
internal import CoreData


class SetService: ServiceBase, ObservableObject {
    @Published var sets: [SessionSet] = []
    @Published var creatingSet: Bool = false
    
    @Published var create_notes: String = ""
    
    @Published var createReps: [SessionRep] = []
    
    //    @Published var ÷
    
    // dont load default
    // sets are assessbilty through sessionexercise
//    override func loadFeature() {
////        self.loadSets()
//    }
    
//    func loadSets() {
        // load sets of a certain set
//    }
    
    func addSet(sessionExercise: SessionExercise) -> SessionSet? {
        let newSet = SessionSet(order: (sessionExercise.sets.count), sessionExercise: sessionExercise, notes: create_notes)
        var failed = false
        withAnimation {
            do {
                modelContext.insert(newSet)
                try modelContext.save()
            } catch {
                failed = true
            }
        }
        
        if (!failed) {return newSet}
        else { return nil }
    }
    
    func completeEditingSet(sessionSet: SessionSet) {
        // Save notes
        if (sessionSet.notes != create_notes) {
            sessionSet.notes = create_notes
            withAnimation {
                try? modelContext.save()
            }
        }
        // reps auto save
        
        self.creatingSet = false
    }
    
    func addRep(sessionSet: SessionSet) {
        
    }
    
    func createNewRep() {
        
    }
    
}
