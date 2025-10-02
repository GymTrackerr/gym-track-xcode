//
//  Exercise.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import Foundation
import SwiftData

@Model
final class Exercise {
    var id: UUID = UUID()
    var npId: String? = nil
    var name: String
    var aliases: [String]? = []
    var type: Int64? = nil
    var muscle_groups: [String]? = []
    var timestamp: Date

    @Relationship(deleteRule: .cascade, inverse: \ExerciseSplitDay.exercise)
    var splits: [ExerciseSplitDay] = []

    init(name:String) {
        self.npId = nil
        self.name = name
        self.timestamp = Date()
    }
}
