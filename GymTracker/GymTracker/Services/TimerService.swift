//
//  TimerService.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-12-06.
//

import Combine
import SwiftUI
import SwiftData

class TimerService: ServiceBase, ObservableObject {
    @Published var timer: TrackerTimer?
    @Published var pendingLength: Int = 0

    private var ticker: AnyCancellable?
    
    override func loadFeature() {
        loadTimer()
        startTicker()
    }
        
    func loadTimer() {
        let descriptor = FetchDescriptor<TrackerTimer>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        
        do {
            let results = try modelContext.fetch(descriptor)
            timer = results.first
            pendingLength = currentUser?.defaultTimer ?? 90
        } catch {
            timer = nil
            print("Failed to fetch timer: \(error)")
        }
    }
    
    private func saveChange() {
        timer?.updatedAt = Date()
        try? modelContext.save()
        objectWillChange.send()
    }
        
    private func startTicker() {
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.objectWillChange.send()
            }
    }
        
    func start() {
        // if the user tapped +15 before start
        let finalLength = pendingLength
        
        let newTimer = TrackerTimer()
        newTimer.timerLength = finalLength
        newTimer.elapsedTime = 0
        newTimer.startTime = Date()
        newTimer.isPaused = false
        newTimer.createdAt = Date()
        newTimer.updatedAt = Date()

        modelContext.insert(newTimer)
        timer = newTimer
//        pendingLength = 0
        saveChange()
    }

    
    func pause() {
        guard let timer, !timer.isPaused, let start = timer.startTime else { return }
        timer.elapsedTime += Int(Date().timeIntervalSince(start))
        timer.startTime = nil
        timer.isPaused = true
        saveChange()
    }
    
    func resume() {
        guard let timer else { return }
        timer.startTime = Date()
        timer.isPaused = false
        saveChange()
    }
    
    func stop(delete: Bool = false) {
        pause()

        if delete, let t = timer {
            modelContext.delete(t)
            self.timer = nil
            try? modelContext.save()
        }

        pendingLength = currentUser?.defaultTimer ?? pendingLength
    }
    
    func adjustPending(seconds: Int) {
        pendingLength = max(pendingLength + seconds, 0)
    }
    
    func add(seconds: Int) {
        guard let timer else {
            adjustPending(seconds: seconds)
            return
        }
        
        timer.timerLength += seconds
        if timer.elapsedTime < 0 { timer.elapsedTime = 0 }
        saveChange()
    }
        
    func subtract(seconds: Int) {
        add(seconds: -seconds)
    }
    
    var displayedTime: Int {
        guard let timer = timer else { return pendingLength }
        if timer.isPaused { return timer.elapsedTime }
        guard let start = timer.startTime else { return timer.elapsedTime }
        return timer.elapsedTime + Int(Date().timeIntervalSince(start))
    }

    var remainingTime: Int? {
        guard let timer = timer else { return nil }
        guard timer.timerLength > 0 else { return nil }   // Count-up mode
        return max(timer.timerLength - displayedTime, 0)
    }

    var formattedPending: String {
        return pendingLength.asTimeString()
    }
    
    var formatted: String {
        if let remaining = remainingTime, remaining >= 0 {
            return remaining.asTimeString()
        } else {
            return displayedTime.asTimeString()
        }
    }
    
    var formattedTimerLength: String {
        guard let timer = timer else {
            return pendingLength.asTimeString()
        }
        
        return timer.timerLength.asTimeString()
    }
}

extension Int {
    func asTimeString() -> String {
        let s = self % 60
        let m = (self / 60) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
