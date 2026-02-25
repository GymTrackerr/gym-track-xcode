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
    @Published var selected_splitDay: Routine? = nil

    private static let poundsFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter
    }()
    
    override func loadFeature() {
        self.loadSessions()
    }
    
    func loadSessions() {
        let descriptor: FetchDescriptor<Session>
        if let userId = currentUser?.id {
            descriptor = FetchDescriptor<Session>(
                predicate: #Predicate<Session> { session in
                    session.user_id == userId
                },
                sortBy: [SortDescriptor(\.timestamp)]
            )
        } else {
            descriptor = FetchDescriptor<Session>(sortBy: [SortDescriptor(\.timestamp)])
        }

        do {
//            sessions = try modelContext.fetch(descriptor)
            
            // migration for timestampDone
            for session in try modelContext.fetch(FetchDescriptor<Session>()) {
                if session.timestampDone == .distantPast || session.timestampDone == Date(timeIntervalSince1970: 0) {
                    session.timestampDone = session.timestamp
                }
            }
            try? modelContext.save()
            
            sessions = try modelContext.fetch(descriptor)


//            let descript2 = FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.order)])
//            var routines:[Routine] = []
//            do {
//                routines = try modelContext.fetch(descript2)
//            } catch {
//                routines = []
//            }
//
//            for session in sessions {
//                print(session.routine)
//                if let routine = session.routine {
            
//
//                } else {
//                    var sesiosnEdit = session
////                    sesiosnEdit.routine_id = nil
//                    try? modelContext.save()
//                }
//                if (session.routine) {
////                    if (session.routine.id)
//                }
//                if (session.routine == null) {
//                    print("null")
//                }
//            }
//            loadSessions()
        } catch {
            sessions = []
        }
    }

    func sessionsInRange(_ interval: DateInterval?) -> [Session] {
        let sortBy = [SortDescriptor(\Session.timestamp, order: .reverse)]

        do {
            let descriptor: FetchDescriptor<Session>

            if let interval {
                let start = interval.start
                let end = interval.end

                if let userId = currentUser?.id {
                    let predicate = #Predicate<Session> {
                        $0.user_id == userId && $0.timestamp >= start && $0.timestamp < end
                    }
                    descriptor = FetchDescriptor(predicate: predicate, sortBy: sortBy)
                } else {
                    let predicate = #Predicate<Session> {
                        $0.timestamp >= start && $0.timestamp < end
                    }
                    descriptor = FetchDescriptor(predicate: predicate, sortBy: sortBy)
                }
            } else if let userId = currentUser?.id {
                let predicate = #Predicate<Session> {
                    $0.user_id == userId
                }
                descriptor = FetchDescriptor(predicate: predicate, sortBy: sortBy)
            } else {
                descriptor = FetchDescriptor(sortBy: sortBy)
            }

            return try modelContext.fetch(descriptor)
        } catch {
            return sessions
                .filter { session in
                    guard let userId = currentUser?.id else { return true }
                    return session.user_id == userId
                }
                .filter { session in
                    guard let interval else { return true }
                    return interval.contains(session.timestamp)
                }
                .sorted { $0.timestamp > $1.timestamp }
        }
    }

    static func sessionVolumeInPounds(_ session: Session) -> Double {
        session.sessionEntries.reduce(0.0) { entryTotal, entry in
            entryTotal + entry.sets.reduce(0.0) { setTotal, sessionSet in
                setTotal + sessionSet.sessionReps.reduce(0.0) { repTotal, rep in
                    let weightInPounds = rep.weight * rep.weightUnit.conversion(to: .lb)
                    return repTotal + (weightInPounds * Double(rep.count))
                }
            }
        }
    }

    static func formattedPounds(_ value: Double) -> String {
        let rounded = value.rounded()
        let formatted = poundsFormatter.string(from: NSNumber(value: rounded)) ?? "0"
        return "\(formatted) lb"
    }
    
    func search(query: String) -> [Session] {
        guard !query.isEmpty else { return sessions }
        return [];
    }
    
    func duplicateSession(session: Session) -> Session? {
        // duplicating exercises only
//        let newSession = Session(timestamp: Date(), routine: session.routine, notes: session.notes)
        selected_splitDay = session.routine
        let newSession = addSession()
        
        if let newSession = newSession {
            withAnimation {
                
            }
            return newSession
        }
        return nil
    }
    
    func addSession() -> Session? {
        print("Adding")
        let trimmedNotes = create_notes.trimmingCharacters(in: .whitespaces)
        guard let userId = currentUser?.id else { return nil }
        
        let newItem = Session(timestamp: Date(), user_id: userId, routine: selected_splitDay, notes: trimmedNotes)
        var failed = false
        
        withAnimation {
            modelContext.insert(newItem)
            try? modelContext.save()

            if let routine = selected_splitDay {
                createSessionExercise(session: newItem, routine: routine)
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
    
    func updateSessionToSplitDay(session: Session) -> Session? {
//        withAnimation {
            session.routine = selected_splitDay
            try? modelContext.save()
            loadSessions()
            return session
//        }
    }
    
    func updateSessionToSplitDay(session: Session, routine: Routine) {
        withAnimation {
            print("updaiting session")
            session.routine = routine
            try? modelContext.save()
            
            createSessionExercise(session: session, routine: routine)
            loadSessions()
        }
    }
    
    // create new session from split day
    func createSessionExercise(session: Session, routine: Routine) {
        // for each exercise in routine
        for (_, exerciseSplit) in routine.exerciseSplits.enumerated() {
            let newSessionEntry = SessionEntry(
                session: session,
                exerciseSplitDay: exerciseSplit
            )
            
            modelContext.insert(newSessionEntry)
            session.sessionEntries.append(newSessionEntry)
        }
    }
    
    func removeSession(session: Session) {
        withAnimation {
            do {
                modelContext.delete(session)
                try modelContext.save()
                loadSessions()
            } catch {
                print("Failed to save after deletion")
            }
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
