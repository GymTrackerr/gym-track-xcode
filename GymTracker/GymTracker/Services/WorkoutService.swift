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

class WorkoutService : ServiceBase, ObservableObject {
    @Published var workouts: [Workout] = []
    
    @Published var create_split_day_id: UUID?
    @Published var create_notes: String?
    @Published var creating_workout: Bool = false
    
    override func loadFeature() {
        self.loadWorkouts()
    }
    
    func loadWorkouts() {
        let descriptor = FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.timestamp)])

        do {
            workouts = try modelContext.fetch(descriptor)
        } catch {
            workouts = []
        }

    }
    
    func search(query: String) -> [Workout] {
        guard !query.isEmpty else { return workouts }
        return [];
    }
    
    func addWorkout() {
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
