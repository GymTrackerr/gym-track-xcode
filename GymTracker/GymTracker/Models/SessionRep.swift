//
//  Rep.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import Foundation
import SwiftData

@Model
final class SessionRep {
    var id: UUID = UUID()
    var weight: Double
    var weight_unit: Int
    var count: Int
    var notes: String?
    
    var sessionSet: SessionSet
    var sessionSet_id: UUID { sessionSet.id }
    
    var weightUnit: WeightUnit {
        WeightUnit(rawValue: weight_unit) ?? WeightUnit.lb
    }

    init(sessionSet: SessionSet, weight: Double, weight_unit: WeightUnit, count: Int, notes: String? = nil) {
        self.sessionSet = sessionSet
        self.weight = weight
        self.weight_unit = weight_unit.rawValue
        self.count = count
        self.notes = notes
    }
}

enum WeightUnit: Int, CaseIterable, Identifiable {
    case lb, kg
    
    var id: Int { return self.rawValue }
    
    var name: String {
        switch self {
        case .lb:
            return "lb"
        case .kg:
            return "kg"
        }
    }

    func conversion(to target: WeightUnit) -> Double {
        switch (self, target) {
        case (.lb, .kg):
            return 0.45359237
        case (.kg, .lb):
            return 2.20462262
        default:
            return 1
        }
    }
}
