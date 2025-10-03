//
//  Workout.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import Foundation
import SwiftData

@Model
final class Session {
    var id: UUID = UUID()
    var timestamp: Date
    var split_day_id: UUID?
    var notes: String?
    
    convenience init (timestamp: Date) {
        self.init(timestamp: timestamp, split_day_id: nil, notes: "")
    }
    
    convenience init(timestamp: Date, split_day_id: UUID?) {
        self.init(timestamp: timestamp, split_day_id: split_day_id, notes: "")
    }

    init (timestamp: Date, split_day_id: UUID?, notes: String) {
        self.timestamp = timestamp
        self.notes = notes
        self.split_day_id = split_day_id
    }
}
