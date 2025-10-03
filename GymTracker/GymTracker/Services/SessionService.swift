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
    
    @Published var create_split_day_id: UUID?
    @Published var create_notes: String?
    @Published var creating_workout: Bool = false
    
    override func loadFeature() {
        self.loadWorkouts()
    }
    
    func loadWorkouts() {
        let descriptor = FetchDescriptor<Session>(sortBy: [SortDescriptor(\.timestamp)])

        do {
            sessions = try modelContext.fetch(descriptor)
        } catch {
            sessions = []
        }

    }
    
    func search(query: String) -> [Session] {
        guard !query.isEmpty else { return sessions }
        return [];
    }
    
    func addSession() {
        print("Adding")
//        let trimmedNotes = create_notes?.trimmingCharacters(in: .whitespaces)
        
        withAnimation {
            do {
                try modelContext.save()
            } catch {
                print("Failed to save new split day: \(error)")
            }
        }
    }

}
