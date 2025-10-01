//
//  Rep.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import Foundation
import SwiftData

@Model
final class Rep {
    var id: UUID = UUID()
    var set_id: UUID
    var weight: Double
    var weight_measurement_unit: Int
    var count: Int
    var notes: String?
    
    init(set_id: UUID, weight: Double, weight_measurement_unit: Int, count: Int, notes: String? = nil) {
        self.set_id = set_id
        self.weight = weight
        self.weight_measurement_unit = weight_measurement_unit
        self.count = count
        self.notes = notes
    }
}
