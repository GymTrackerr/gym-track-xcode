//
//  SplitDay.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import Foundation
import SwiftData

@Model
final class SplitDay {
    var id: UUID = UUID()
    var order: Int
    var name: String
    var timestamp: Date
    
    init(order: Int, name: String) {
        self.order = order
        self.name = name
        self.timestamp = Date()
    }
}
