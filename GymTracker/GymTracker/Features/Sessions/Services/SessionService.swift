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
    @Published var selectedProgram: Program? = nil
    @Published var selectedProgramWorkout: ProgramWorkout? = nil

    private static let poundsFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter
    }()
    private let repository: SessionRepositoryProtocol
    var progressionService: ProgressionService?

    init(context: ModelContext, repository: SessionRepositoryProtocol? = nil) {
        self.repository = repository ?? LocalSessionRepository(modelContext: context)
        super.init(context: context)
    }
    
    override func loadFeature() {
        self.loadSessions()
    }
    
    func loadSessions() {
        do {
            sessions = try repository.fetchSessions(for: currentUser?.id)
        } catch {
            sessions = []
        }
    }

    func sessionsInRange(_ interval: DateInterval?) -> [Session] {
        sessions
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
        selectedProgram = nil
        selectedProgramWorkout = nil
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
        
        var newItem: Session?
        var failed = false
        
        withAnimation {
            do {
                if let selectedProgram, let selectedProgramWorkout {
                    let programBlock = selectedProgramWorkout.programBlock
                    newItem = try repository.createProgramSession(
                        userId: userId,
                        program: selectedProgram,
                        programBlock: programBlock,
                        programWorkout: selectedProgramWorkout,
                        notes: trimmedNotes,
                        programWeekIndex: currentProgramWeekIndex(for: selectedProgram, block: programBlock),
                        programSplitIndex: currentProgramSplitIndex(for: programBlock)
                    )
                } else {
                    newItem = try repository.createSession(userId: userId, routine: selected_splitDay, notes: trimmedNotes)
                }
                if let newItem {
                    progressionService?.applySnapshots(to: newItem)
                }
                resetCreationState()
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

    func startProgramWorkout(program: Program, workout: ProgramWorkout) -> Session? {
        selectedProgram = program
        selectedProgramWorkout = workout
        selected_splitDay = workout.routine
        return addSession()
    }

    func selectRoutine(_ routine: Routine?) {
        selected_splitDay = routine
        selectedProgram = nil
        selectedProgramWorkout = nil
    }

    func selectProgramWorkout(program: Program, workout: ProgramWorkout) {
        selectedProgram = program
        selectedProgramWorkout = workout
        selected_splitDay = workout.routine
    }

    func resetCreationState() {
        creating_session = false
        create_notes = ""
        selected_splitDay = nil
        selectedProgram = nil
        selectedProgramWorkout = nil
    }
    
    func updateSessionToSplitDay(session: Session) -> Session? {
            try? repository.updateRoutine(for: session, routine: selected_splitDay)
            loadSessions()
            return session
    }
    
    func updateSessionToSplitDay(session: Session, routine: Routine) {
        withAnimation {
            print("updaiting session")
            try? repository.updateRoutine(for: session, routine: routine)
            loadSessions()
        }
    }
    
    func removeSession(session: Session) {
        withAnimation {
            do {
                try repository.deleteSession(session)
                loadSessions()
            } catch {
                print("Failed to save after deletion")
            }
        }
    }
    
    func removeSession(offsets: IndexSet) {
        // TODO: OFFSETS IS WRONG?
        withAnimation {
            do {
                let sessionsToDelete = offsets.compactMap { sessions.indices.contains($0) ? sessions[$0] : nil }
                try repository.deleteSessions(sessionsToDelete)
                loadSessions()
            } catch {
                print("Failed to save after deletion")
            }
        }
    }

    func finishSession(_ session: Session) {
        guard session.timestampDone == session.timestamp else { return }
        session.timestampDone = Date()
        do {
            try repository.saveChanges(for: session)
            progressionService?.evaluateIfNeeded(for: session)
            loadSessions()
        } catch {
            print("Failed to finish session: \(error)")
        }
    }

    private func currentProgramWeekIndex(for program: Program, block: ProgramBlock) -> Int? {
        guard program.mode == .weekly else { return nil }
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: program.startDate)
        let today = calendar.startOfDay(for: Date())
        let dayOffset = max(calendar.dateComponents([.day], from: startDate, to: today).day ?? 0, 0)
        let elapsedWeeks = dayOffset / 7
        let previousWeeks = program.blocks
            .filter { $0.order < block.order }
            .reduce(0) { $0 + max($1.durationCount, 1) }
        return max((elapsedWeeks - previousWeeks) + 1, 1)
    }

    private func currentProgramSplitIndex(for block: ProgramBlock) -> Int? {
        guard block.program.mode == .continuous else { return nil }
        let workoutsCount = max(block.workouts.count, 1)
        let completedCount = sessions.filter {
            $0.programBlockId == block.id && $0.timestampDone != $0.timestamp && !$0.soft_deleted
        }.count
        return (completedCount / workoutsCount) + 1
    }

}
