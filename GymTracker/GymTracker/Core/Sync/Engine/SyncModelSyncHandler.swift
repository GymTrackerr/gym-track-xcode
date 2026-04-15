//
//  SyncModelSyncHandler.swift
//  GymTracker
//
//  Created by Codex on 2026-04-16.
//

import Foundation

protocol SyncModelSyncHandler {
    var modelType: SyncModelType { get }
    func process(item: SyncQueueItem) async throws
}
