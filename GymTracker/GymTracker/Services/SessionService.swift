//
//  WorkoutService.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-02.
//

import SwiftUI
import SwiftData
import Combine
internal import CoreData

class SessionService : ServiceBase, ObservableObject {
    @Published var sessions: [Session] = []
    
    @Published var create_notes: String = ""
    @Published var creating_session: Bool = false
    @Published var selected_splitDay: SplitDay? = nil
    
    override func loadFeature() {
        self.loadSessions()
    }
    
    func loadSessions() {
        let descriptor = FetchDescriptor<Session>(sortBy: [SortDescriptor(\.timestamp)])

        do {
            sessions = try modelContext.fetch(descriptor)
//            let descript2 = FetchDescriptor<SplitDay>(sortBy: [SortDescriptor(\.order)])
//            var splitDays:[SplitDay] = []
//            do {
//                splitDays = try modelContext.fetch(descript2)
//            } catch {
//                splitDays = []
//            }
//
//            for session in sessions {
//                print(session.splitDay)
//                if let splitDay = session.splitDay {
//                    
//                } else {
//                    var sesiosnEdit = session
////                    sesiosnEdit.split_day_id = nil
//                    try? modelContext.save()
//                }
//                if (session.splitDay) {
////                    if (session.splitDay.id)
//                }
//                if (session.splitDay == null) {
//                    print("null")
//                }
//            }
//            loadSessions()
        } catch {
            sessions = []
        }
    }
    
    func search(query: String) -> [Session] {
        guard !query.isEmpty else { return sessions }
        return [];
    }
    
    func addSession() -> Session? {
        print("Adding")
        let trimmedNotes = create_notes.trimmingCharacters(in: .whitespaces)
        
        let newItem = Session(timestamp: Date(), splitDay: selected_splitDay, notes: trimmedNotes)
        var failed = false
        
        withAnimation {
            modelContext.insert(newItem)
            try? modelContext.save()

            if let splitDay = selected_splitDay {
                createSessionExercise(session: newItem, splitDay: splitDay)
            }
        
            do {
                try modelContext.save()
                creating_session = false
                create_notes = ""
                selected_splitDay = nil
                loadSessions()
            } catch {
                print("Failed to save new split day: \(error)")
                failed = true
            }
        }
        
        if (failed==true) {
            return nil
        }
        
        return newItem
    }
    
    func updateSessionToSplitDay(session: Session) {
        withAnimation {
            session.splitDay = selected_splitDay
            try? modelContext.save()
            loadSessions()
        }
    }
    
    func updateSessionToSplitDay(session: Session, splitDay: SplitDay) {
        withAnimation {
            print("updaiting session")
            session.splitDay = splitDay
            try? modelContext.save()
            
            createSessionExercise(session: session, splitDay: splitDay)
            loadSessions()
        }
    }
    
    // create new session from split day
    func createSessionExercise(session:Session, splitDay: SplitDay) {
        // for each exercise in splitDay
        for (_, exerciseSplit) in splitDay.exerciseSplits.enumerated() {
            let newSessionExercise = SessionExercise(
                session: session,
                exerciseSplitDay: exerciseSplit
            )
            
            modelContext.insert(newSessionExercise)
        }
    }
    
    func removeSession(offsets: IndexSet) {
        // TODO: OFFSETS IS WRONG?
        withAnimation {
            for index in offsets {
                modelContext.delete(sessions[index])
            }
            
            do {
                try modelContext.save()
                loadSessions()
            } catch {
                print("Failed to save after deletion")
            }
        }
    }

}
