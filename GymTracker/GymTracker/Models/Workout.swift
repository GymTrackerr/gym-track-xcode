//
//  Workout.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import Foundation
import SwiftData

@Model
final class Workout {
    var id: UUID = UUID()
    var split_day_id: UUID?
    var notes: String?
    var timestamp: Date
    
    init (split_day_id: UUID?=nil, notes: String?, timestamp: Date) {
        self.split_day_id = split_day_id
        self.notes = notes
        self.timestamp = timestamp
    }
}
