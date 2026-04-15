//
//  SyncRootSnapshotPayload.swift
//  GymTracker
//
//  Created by Codex on 2026-04-15.
//

import Foundation

struct SyncRootSnapshotPayload: Codable {
    let modelTypeRaw: Int
    let linkedItemId: String
    let createdAt: Date
    let updatedAt: Date
    let softDeleted: Bool

    init<Root: SyncTrackedRoot>(_ root: Root) {
        self.modelTypeRaw = Root.syncModelType.rawValue
        self.linkedItemId = root.syncLinkedItemId
        self.createdAt = root.createdAt
        self.updatedAt = root.updatedAt
        self.softDeleted = root.soft_deleted
    }
}
