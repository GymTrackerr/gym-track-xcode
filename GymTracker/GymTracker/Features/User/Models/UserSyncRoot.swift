//
//  UserSyncRoot.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2026-04-15.
//

import Foundation
import SwiftData

extension User: SyncTrackedRoot {
    static var syncModelType: SyncModelType { .userProfile }
    var syncLinkedItemId: String { id.uuidString.lowercased() }
    var syncSeedDate: Date { timestamp }
}

