//
//  TimerService.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-12-06.
//

import Combine
import SwiftUI
import SwiftData
#if os(iOS)
import ActivityKit
#endif

class TimerService: ServiceBase, ObservableObject {
    @Published var timer: TrackerTimer?
    @Published var pendingLength: Int = 90

    private var ticker: AnyCancellable?
    private var hadTimerBefore = false
    private var timerWasLocallyUpdated = false

    override func loadFeature() {
        loadTimer()
        if timer != nil { startTicker() }
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
        timerWasLocallyUpdated = true
        timer?.updatedAt = Date()
        try? modelContext.save()
    }
    
    private func startTicker() {
        ticker?.cancel()
        
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                
                if !self.timerWasLocallyUpdated {
                    self.loadTimer()   // Only reload if widget changed it
                }
                self.timerWasLocallyUpdated = false
                
                guard let timer = self.timer else {
                    if self.hadTimerBefore {
                        self.endLiveActivity()
                        self.hadTimerBefore = false
                        self.stopTicker()
                    }
                    return
                }
                
                self.hadTimerBefore = true
                
                if !timer.isPaused, let remaining = self.remainingTime, remaining <= 0 {
                    self.handleTimerFinished()
                    return
                }
                
                self.updateLiveActivity()
                self.objectWillChange.send()
            }
    }
    
    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }
    
    private func deleteTimerModel() {
        if let t = timer {
            modelContext.delete(t)
            timer = nil
            try? modelContext.save()
        }
    }
    
    private func handleTimerFinished() {
        pause()
        deleteTimerModel()
        endLiveActivity(after: 3)
    }
    
    func updateDefaultTimer(sec: Int) {
        currentUser?.defaultTimer = sec
        try? modelContext.save()
    }
    
    func start() {
        self.hapticPress()
        
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
        
        saveChange()
        startLiveActivity()
        
        if ticker == nil { startTicker() }
    }

    
    func pause() {
        guard let timer, !timer.isPaused, let start = timer.startTime else { return }
        timer.elapsedTime += Int(Date().timeIntervalSince(start))
        timer.startTime = nil
        timer.isPaused = true
        saveChange()
        updateLiveActivity()
    }
        
    func resume() {
        guard let timer else { return }
        self.hapticPress()
        timer.startTime = Date()
        timer.isPaused = false
        saveChange()
        updateLiveActivity()
    }
    
    func stop(delete: Bool = false) {
        self.hapticPress()
        pause()
        if let timerLength = timer?.timerLength {
            if (timerLength != pendingLength) {
                pendingLength = timerLength
            }
        }
      
        if delete { deleteTimerModel() }

        hadTimerBefore = false
        stopTicker()
        endLiveActivity()
    }

    func adjustPending(seconds: Int) {
        pendingLength = max(pendingLength + seconds, 0)
    }

    func add(seconds: Int) {
        self.hapticPress()
        updateDefaultTimer(sec: (pendingLength+seconds))
        guard let timer else {
            adjustPending(seconds: seconds)
            return
        }
        
        timer.timerLength += seconds
        if timer.elapsedTime < 0 { timer.elapsedTime = 0 }
        
        saveChange()
        updateLiveActivity()
    }
        
    func subtract(seconds: Int) {
        add(seconds: -seconds)
    }
    
    var isFinished: Bool {
        return timer == nil && displayedTime == 0 && pendingLength > 0
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
    
    func appDidEnterBackground() {
        // Ticker keeps running to update live activity in background
    }

    func appDidBecomeActive() {
        loadTimer()
        updateLiveActivity()
    }

}

extension Int {
    func asTimeString() -> String {
        let s = self % 60
        let m = (self / 60) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
