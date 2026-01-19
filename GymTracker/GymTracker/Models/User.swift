//
//  User.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-03.
//

import Foundation
import SwiftData

@Model
final class User {
    var id: UUID = UUID()
    var name: String
    var timestamp: Date
    var lastLogin: Date
    var active: Bool = true
    var allowHealthAccess: Bool = false
    
    var defaultTimer: Int = 90
    
    init(name: String) {
        self.name = name
        self.timestamp = Date()
        self.lastLogin = Date()
    }
}
