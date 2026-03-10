//
//  TimerDataController.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-12-07.
//

import SwiftData
import Foundation

@MainActor
struct TimerDataController {
    private static let appGroupIdentifier = "group.net.novapro.GymTracker"

    static let container: ModelContainer? = {
        let schema = Schema([TrackerTimer.self])
        guard let url = containerURL() else {
            print("TimerDataController: app group container URL unavailable.")
            return nil
        }

        let modelConfiguration = ModelConfiguration(schema: schema, url: url)
        var lastError: Error?

        for attempt in 1...3 {
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                lastError = error
                print("TimerDataController: container init attempt \(attempt) failed: \(error)")
                Thread.sleep(forTimeInterval: 0.15)
            }
        }

        print("TimerDataController: failed to initialize shared container after retries: \(String(describing: lastError))")
        return nil
    }()
    
    static var context: ModelContext? {
        container?.mainContext
    }

    private static func containerURL() -> URL? {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return nil
        }
        return url.appendingPathComponent("gym_tracker.sqlite")
    }
    
    static func fetchTimer(byId id: String) -> TrackerTimer? {
        guard let uuid = UUID(uuidString: id) else {
            return nil
        }
        guard let context else {
            print("TimerDataController: missing model context while fetching timer.")
            return nil
        }
        
        do {
            let descriptor = FetchDescriptor<TrackerTimer>(
                predicate: #Predicate { $0.id == uuid }
            )
            let timers = try context.fetch(descriptor)
            return timers.first
        } catch {
            print("Failed to fetch timer by ID: \(error)")
            return nil
        }
    }
    
    static func getTimerInfo(byId id: String) -> (elapsedTime: Int, isPaused: Bool, timerLength: Int)? {
        guard let timer = fetchTimer(byId: id) else {
            print("Could not find timer with ID: \(id)")
            return nil
        }
        
        let currentElapsed: Int
        if timer.isPaused {
            currentElapsed = timer.elapsedTime
        } else if let startTime = timer.startTime {
            currentElapsed = timer.elapsedTime + Int(Date().timeIntervalSince(startTime))
        } else {
            currentElapsed = timer.elapsedTime
        }
        
        print("Timer info - elapsed: \(currentElapsed)s, paused: \(timer.isPaused), total: \(timer.timerLength)s")
        return (elapsedTime: currentElapsed, isPaused: timer.isPaused, timerLength: timer.timerLength)
    }
}
