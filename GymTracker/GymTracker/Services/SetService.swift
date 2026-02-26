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
        let newSet = SessionSet(order: sessionEntry.sets.count, sessionEntry: sessionEntry, notes: notes)
        newSet.isDropSet = isDropSet
        var failed = false

        withAnimation {
            do {
                modelContext.insert(newSet)
                sessionEntry.sets.append(newSet)
                try modelContext.save()
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
                try? modelContext.save()
            }
        }
        
        // reps auto save
        self.creatingSet = false
    }
    
    func createBlankRep(sessionSet: SessionSet) -> SessionRep? {
        let newRep = SessionRep(
            sessionSet: sessionSet,
            weight: 0,
            weight_unit: WeightUnit.lb,
            count: 0
        )

        var failedSave = false
        createReps.append(newRep)
        withAnimation {
            do {
                sessionSet.sessionReps.append(newRep)
                try modelContext.save()
            } catch {
                failedSave = true
            }
        }

        if (failedSave) { return nil }
        return newRep
    }

    @discardableResult
    func addRep(sessionSet: SessionSet, weight: Double, reps: Int, unit: WeightUnit) -> SessionRep? {
        let newRep = SessionRep(
            sessionSet: sessionSet,
            weight: weight,
            weight_unit: unit,
            count: reps
        )

        withAnimation {
            sessionSet.sessionReps.append(newRep)
            try? modelContext.save()
        }

        return newRep
    }

    func deleteRep(sessionSet: SessionSet, rep: SessionRep) {
        sessionSet.sessionReps.removeAll { $0.id == rep.id }
        modelContext.delete(rep)
        if sessionSet.sessionReps.count <= 1 {
            sessionSet.isDropSet = false
        }
        withAnimation {
            try? modelContext.save()
        }
    }

    func deleteSet(sessionEntry: SessionEntry, sessionSet: SessionSet) {
        sessionEntry.sets.removeAll { $0.id == sessionSet.id }
        modelContext.delete(sessionSet)
        reorderSets(sessionEntry: sessionEntry)
        withAnimation {
            try? modelContext.save()
        }
    }

    func moveSet(_ sessionSet: SessionSet, to targetExercise: Exercise) throws {
        let sourceEntry = sessionSet.sessionEntry
        let session = sourceEntry.session
        guard sourceEntry.exercise.id != targetExercise.id else { return }

        let targetEntry = SessionEntryResolver.ensureSessionEntry(
            for: targetExercise,
            in: session,
            context: modelContext
        )

        sourceEntry.sets.removeAll { $0.id == sessionSet.id }
        sessionSet.sessionEntry = targetEntry
        sessionSet.order = targetEntry.sets.count
        targetEntry.sets.append(sessionSet)

        reorderSets(sessionEntry: sourceEntry)
        if sourceEntry.id != targetEntry.id {
            reorderSets(sessionEntry: targetEntry)
        }

        try modelContext.save()
    }

    private func recentEntries(for exercise: Exercise) -> [SessionEntry] {
        let descriptor = FetchDescriptor<SessionEntry>()
        let allEntries = (try? modelContext.fetch(descriptor)) ?? []
        return allEntries
            .filter { $0.exercise.id == exercise.id }
            .sorted { $0.session.timestamp > $1.session.timestamp }
    }

    func mostRecentRep(for exercise: Exercise) -> SessionRep? {
        for entry in recentEntries(for: exercise) {
            let sortedSets = entry.sets.sorted { $0.timestamp > $1.timestamp }
            for sessionSet in sortedSets {
                for rep in sessionSet.sessionReps.reversed() {
                    if rep.weight > 0 || rep.count > 0 {
                        return rep
                    }
                }
            }
        }
        return nil
    }

    func mostRecentCardioSet(for exercise: Exercise) -> SessionSet? {
        for entry in recentEntries(for: exercise) {
            let sortedSets = entry.sets.sorted { $0.timestamp > $1.timestamp }
            for sessionSet in sortedSets where isMeaningfulCardioSet(sessionSet) {
                return sessionSet
            }
        }
        return nil
    }

    private func isMeaningfulCardioSet(_ sessionSet: SessionSet) -> Bool {
        let hasDuration = (sessionSet.durationSeconds ?? 0) > 0
        let hasDistance = (sessionSet.distance ?? 0) > 0
        let hasPace = (sessionSet.paceSeconds ?? 0) > 0
        return hasDuration || hasDistance || hasPace
    }

    private func reorderSets(sessionEntry: SessionEntry) {
        let sortedSets = sessionEntry.sets.sorted { $0.order < $1.order }
        for (index, set) in sortedSets.enumerated() {
            set.order = index
        }
    }

    func addRep(sessionSet: SessionSet) {
        
    }
    
    func createNewRep() {
        
    }
    
    func saveSetData(sessionSet: SessionSet) {
        withAnimation {
            try? modelContext.save()
        }
    }
    

    func saveRepData(sessionRep: SessionRep) {
        withAnimation {
            try? modelContext.save()
        }
    }
    
    func toggleSetCompletion(sessionSet: SessionSet) {
        withAnimation {
            sessionSet.isCompleted.toggle()
            try? modelContext.save()
        }
    }
}
