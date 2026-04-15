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
    private let repository: SessionRepositoryProtocol

    init(context: ModelContext, repository: SessionRepositoryProtocol? = nil) {
        self.repository = repository ?? LocalSessionRepository(modelContext: context)
        super.init(context: context)
    }
    
    //    @Published var ÷
    
    // dont load default
    // sets are assessbilty through session entry
//    override func loadFeature() {
////        self.loadSets()
//    }
    
//    func loadSets() {
        // load sets of a certain set
//    }
    
    
    func getSetRepCount(sessionSet: SessionSet) -> Int {
        var totalRepCount: Int = 0
        for rep in sessionSet.sessionReps {
            totalRepCount += rep.count
        }
        
        return totalRepCount
    }
    
    func getSetWorkload(sessionSet: SessionSet) -> Int {
        var totalWorkload: Double = 0
        for rep in sessionSet.sessionReps {
            totalWorkload += (rep.weight*Double(rep.count))
        }
        

        return Int(round(totalWorkload))
    }
    
    func addSet(sessionEntry: SessionEntry, notes: String, isDropSet: Bool) -> SessionSet? {
        var failed = false
        var newSet: SessionSet?

        withAnimation {
            do {
                newSet = try repository.addSet(to: sessionEntry, notes: notes, isDropSet: isDropSet)
            } catch {
                failed = true
            }
        }

        if (!failed) { return newSet }
        return nil
    }
    
    func completeEditingSet(sessionSet: SessionSet) {
        // Save notes
        if (sessionSet.notes != create_notes) {
            sessionSet.notes = create_notes
            withAnimation {
                try? repository.saveChanges()
            }
        }
        
        // reps auto save
        self.creatingSet = false
    }
    
    func createBlankRep(sessionSet: SessionSet) -> SessionRep? {
        var failedSave = false
        var newRep: SessionRep?
        withAnimation {
            do {
                let created = try repository.createBlankRep(in: sessionSet)
                createReps.append(created)
                newRep = created
            } catch {
                failedSave = true
            }
        }

        if (failedSave) { return nil }
        return newRep
    }

    @discardableResult
    func addRep(sessionSet: SessionSet, weight: Double, reps: Int, unit: WeightUnit) -> SessionRep? {
        var newRep: SessionRep?
        withAnimation {
            newRep = try? repository.addRep(to: sessionSet, weight: weight, reps: reps, unit: unit)
        }

        return newRep
    }

    func deleteRep(sessionSet: SessionSet, rep: SessionRep) {
        withAnimation {
            try? repository.deleteRep(from: sessionSet, rep: rep)
        }
    }

    func deleteSet(sessionEntry: SessionEntry, sessionSet: SessionSet) {
        withAnimation {
            try? repository.deleteSet(from: sessionEntry, sessionSet: sessionSet)
        }
    }

    @discardableResult
    func duplicateSet(_ sessionSet: SessionSet) -> SessionSet? {
        var failed = false
        var duplicate: SessionSet?
        withAnimation {
            do {
                duplicate = try repository.duplicateSet(sessionSet)
            } catch {
                failed = true
            }
        }

        if failed { return nil }
        return duplicate
    }

    func moveSet(_ sessionSet: SessionSet, to targetExercise: Exercise) throws {
        try repository.moveSet(sessionSet, to: targetExercise)
    }

    func mostRecentRep(for exercise: Exercise) -> SessionRep? {
        repository.mostRecentRep(for: exercise)
    }

    func mostRecentCardioSet(for exercise: Exercise) -> SessionSet? {
        repository.mostRecentCardioSet(for: exercise)
    }

    func saveSetData(sessionSet: SessionSet) {
        withAnimation {
            try? repository.saveChanges()
        }
    }
    

    func saveRepData(sessionRep: SessionRep) {
        withAnimation {
            try? repository.saveChanges()
        }
    }
    
    func toggleSetCompletion(sessionSet: SessionSet) {
        withAnimation {
            try? repository.toggleSetCompletion(sessionSet)
        }
    }
}
