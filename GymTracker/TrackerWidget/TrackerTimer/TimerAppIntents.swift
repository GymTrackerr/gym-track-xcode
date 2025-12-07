//
//  TimerAppIntents.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-12-07.
//

import AppIntents
import SwiftData
import UserNotifications

struct PauseTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause Timer"
    
    @MainActor
    func perform() async throws -> some IntentResult {
        let context = TimerDataController.context
        
        let descriptor = FetchDescriptor<TrackerTimer>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        guard let timer = try? context.fetch(descriptor).first else {
            return .result()
        }

        if let start = timer.startTime {
            timer.elapsedTime += Int(Date().timeIntervalSince(start))
        }
        timer.isPaused = true
        timer.startTime = nil
        
        try? context.save()

        return .result()
    }
}

struct ResumeTimerIntent: AppIntent {
    static var title:LocalizedStringResource = "Resume Timer"
    
    @MainActor
    func perform() async throws -> some IntentResult {
        let context = TimerDataController.context
        
        let descriptor = FetchDescriptor<TrackerTimer>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        
        guard let timer = try? context.fetch(descriptor).first else {
            return .result()
        }

        timer.isPaused = false
        timer.startTime = Date()
        
        try? context.save()
        
        return .result()
    }
}

struct CancelTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Cancel Timer"
    
    @MainActor
    func perform() async throws -> some IntentResult {
        let context = TimerDataController.context
        
        let descriptor = FetchDescriptor<TrackerTimer>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        if let timer = try? context.fetch(descriptor).first {
            context.delete(timer)
            try? context.save()
        }
        
        return .result()
    }
}
