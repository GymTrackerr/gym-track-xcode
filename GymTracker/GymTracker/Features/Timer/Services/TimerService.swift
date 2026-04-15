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
import UserNotifications
#endif

class TimerService: ServiceBase, ObservableObject {
    @Published var timer: TrackerTimer?
    @Published var pendingLength: Int = 90

    private var ticker: AnyCancellable?
    private var hadTimerBefore = false
    private var timerWasLocallyUpdated = false
    private var isApplyingPendingTimerCommand = false
    private var lastLiveActivitySyncAt = Date.distantPast
    private var lastTimerStateSyncAt = Date.distantPast
    private let liveActivityResyncInterval: TimeInterval = 2
    private let appGroupIdentifier = "group.net.novapro.GymTracker"
    private let pendingTimerControlCommandKey = "pendingTimerControlCommand"
    private let timerFinishedNotificationId = "timer.finished.active"
    private let awayTooLongNotificationId = "timer.away-too-long.active"
    private var lastLifecycleEvent: TimerLifecycleEvent?
    private var isAppInForeground = true

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
                guard !self.isApplyingPendingTimerCommand else { return }

                if self.timer == nil && !self.timerWasLocallyUpdated {
                    self.loadTimer()
                }

                if self.applyPendingTimerControlCommandIfNeeded() {
                    return
                }
                
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

                if timer.updatedAt > self.lastTimerStateSyncAt {
                    self.lastTimerStateSyncAt = timer.updatedAt
                    self.syncLiveActivity(force: true)
                }
                
                if !timer.isPaused, let remaining = self.remainingTime, remaining <= 0 {
                    self.handleTimerFinished()
                    return
                }
                
                self.syncLiveActivity(force: false)
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
        emitLifecycleEvent(.completed, completedAt: Date())
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
        clearPendingTimerControlCommand()
        
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
        syncLiveActivity(force: true)
        lastTimerStateSyncAt = newTimer.updatedAt
        emitLifecycleEvent(.started)
        
        if ticker == nil { startTicker() }
    }

    
    func pause() {
        guard let timer, !timer.isPaused, let start = timer.startTime else { return }
        timer.elapsedTime += Int(Date().timeIntervalSince(start))
        timer.startTime = nil
        timer.isPaused = true
        saveChange()
        syncLiveActivity(force: true)
        emitLifecycleEvent(.paused)
    }
        
    func resume() {
        guard let timer else { return }
        self.hapticPress()
        timer.startTime = Date()
        timer.isPaused = false
        saveChange()
        syncLiveActivity(force: true)
        emitLifecycleEvent(.resumed)
    }
    
    func stop(delete: Bool = false) {
        self.hapticPress()
        pause()
        if let timerLength = timer?.timerLength {
            if (timerLength != pendingLength) {
                pendingLength = timerLength
            }
        }
      
        if delete {
            emitLifecycleEvent(.cancelled, cancelledAt: Date())
            deleteTimerModel()
        }

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
        syncLiveActivity(force: true)
        emitLifecycleEvent(.adjusted)
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
        isAppInForeground = false
        syncLiveActivity(force: true)
        emitLifecycleEvent(.appBackgrounded)
    }

    func appDidBecomeActive() {
        isApplyingPendingTimerCommand = true
        stopTicker()

        isAppInForeground = true
        loadTimer()
        applyPendingTimerControlCommandIfNeeded()
        if let timer {
            lastTimerStateSyncAt = timer.updatedAt
            startTicker()
        }
        syncLiveActivity(force: true)
        cancelAwayTooLongNotification()
        emitLifecycleEvent(.appForegrounded)

        isApplyingPendingTimerCommand = false
    }

    private func syncLiveActivity(force: Bool) {
        guard let timer else { return }
        if !force {
            guard !timer.isPaused else { return }
            let now = Date()
            guard now.timeIntervalSince(lastLiveActivitySyncAt) >= liveActivityResyncInterval else { return }
        }
        updateLiveActivity()
        lastLiveActivitySyncAt = Date()
    }

    private func applyPendingTimerControlCommandIfNeeded() -> Bool {
        struct PendingTimerControlCommand: Codable {
            let action: String
            let remainingSeconds: Int?
            let requestedAt: TimeInterval
            let timerId: String
        }

        guard
            let defaults = UserDefaults(suiteName: appGroupIdentifier),
            let data = defaults.data(forKey: pendingTimerControlCommandKey),
            let command = try? JSONDecoder().decode(PendingTimerControlCommand.self, from: data)
        else {
            return false
        }

        if let timer = timer,
           command.timerId.isEmpty == false,
           timer.id.uuidString.lowercased() != command.timerId.lowercased() {
            defaults.removeObject(forKey: pendingTimerControlCommandKey)
            return false
        }

        defaults.removeObject(forKey: pendingTimerControlCommandKey)
        isApplyingPendingTimerCommand = true
        defer { isApplyingPendingTimerCommand = false }

        switch command.action {
        case "pause":
            guard let timer else { return false }
            let remaining = command.remainingSeconds ?? max(timer.timerLength - displayedTime, 0)
            timer.elapsedTime = max(timer.timerLength - remaining, 0)
            timer.startTime = nil
            timer.isPaused = true
            saveChange()
            syncLiveActivity(force: true)
            emitLifecycleEvent(.paused)

        case "resume":
            guard let timer else { return false }
            let remaining = command.remainingSeconds ?? max(timer.timerLength - displayedTime, 0)
            timer.elapsedTime = max(timer.timerLength - remaining, 0)
            timer.startTime = Date()
            timer.isPaused = false
            saveChange()
            syncLiveActivity(force: true)
            emitLifecycleEvent(.resumed)

        case "cancel":
            if timer != nil {
                stop(delete: true)
            }

        default:
            return false
        }

        return true
    }

    private func clearPendingTimerControlCommand() {
        UserDefaults(suiteName: appGroupIdentifier)?.removeObject(forKey: pendingTimerControlCommandKey)
    }

    private func emitLifecycleEvent(
        _ eventType: TimerLifecycleEventType,
        completedAt: Date? = nil,
        cancelledAt: Date? = nil
    ) {
        guard let timer else { return }

        let event = TimerLifecycleEvent(
            eventType: eventType,
            timerId: timer.id.uuidString,
            status: timerLifecycleStatus(for: eventType, timer: timer),
            remainingDurationSeconds: max(remainingTime ?? 0, 0),
            totalDurationSeconds: max(timer.timerLength, 0),
            effectiveAt: Date(),
            completedAt: completedAt,
            cancelledAt: cancelledAt
        )

        lastLifecycleEvent = event
        handleLifecycleEvent(event)
    }

    private func timerLifecycleStatus(for eventType: TimerLifecycleEventType, timer: TrackerTimer) -> TimerLifecycleStatus {
        switch eventType {
        case .completed:
            return .completed
        case .cancelled:
            return .cancelled
        default:
            return timer.isPaused ? .paused : .running
        }
    }

    private func handleLifecycleEvent(_ event: TimerLifecycleEvent) {
        switch event.eventType {
        case .started, .resumed, .adjusted:
            scheduleTimerFinishedNotificationIfNeeded()
            cancelAwayTooLongNotification()
        case .paused, .cancelled, .completed:
            cancelTimerFinishedNotification()
            if event.eventType != .completed {
                cancelAwayTooLongNotification()
            } else {
                scheduleAwayTooLongNotificationIfNeeded(completedAt: event.completedAt ?? event.effectiveAt)
            }
        case .appBackgrounded, .appForegrounded:
            if event.eventType == .appForegrounded {
                cancelAwayTooLongNotification()
            }
            break
        }
    }

    private var timerNotificationsEnabled: Bool {
        currentUser?.timerNotificationsEnabled ?? true
    }

    private var timerFinishedNotificationEnabled: Bool {
        currentUser?.timerFinishedNotificationEnabled ?? true
    }

    private var awayTooLongEnabled: Bool {
        currentUser?.awayTooLongEnabled ?? false
    }

    private var awayTooLongMinutes: Int {
        max(currentUser?.awayTooLongMinutes ?? 10, 1)
    }

    private func scheduleTimerFinishedNotificationIfNeeded() {
        #if os(iOS)
        guard timerNotificationsEnabled, timerFinishedNotificationEnabled else {
            cancelTimerFinishedNotification()
            return
        }
        guard let timer, !timer.isPaused, let remaining = remainingTime, remaining > 0 else {
            cancelTimerFinishedNotification()
            return
        }

        let seconds = TimeInterval(max(remaining, 1))
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }

            center.removePendingNotificationRequests(withIdentifiers: [timerFinishedNotificationId])

            let content = UNMutableNotificationContent()
            content.title = "Timer Finished"
            content.body = "Your workout timer is done."
            content.sound = .default
            content.userInfo = ["timerId": timer.id.uuidString]

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
            let request = UNNotificationRequest(identifier: timerFinishedNotificationId, content: content, trigger: trigger)
            try? await center.add(request)
        }
        #endif
    }

    private func cancelTimerFinishedNotification() {
        #if os(iOS)
        Task {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [timerFinishedNotificationId])
        }
        #endif
    }

    private func scheduleAwayTooLongNotificationIfNeeded(completedAt: Date) {
        #if os(iOS)
        guard !isAppInForeground else {
            cancelAwayTooLongNotification()
            return
        }
        guard timerNotificationsEnabled, awayTooLongEnabled else {
            cancelAwayTooLongNotification()
            return
        }

        let delaySeconds = TimeInterval(awayTooLongMinutes * 60)
        let fireIn = max(completedAt.addingTimeInterval(delaySeconds).timeIntervalSinceNow, 1)

        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }

            center.removePendingNotificationRequests(withIdentifiers: [awayTooLongNotificationId])

            let content = UNMutableNotificationContent()
            content.title = "Still Away?"
            content.body = "Your timer finished a while ago. Jump back in when you're ready."
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fireIn, repeats: false)
            let request = UNNotificationRequest(identifier: awayTooLongNotificationId, content: content, trigger: trigger)
            try? await center.add(request)
        }
        #endif
    }

    private func cancelAwayTooLongNotification() {
        #if os(iOS)
        Task {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [awayTooLongNotificationId])
        }
        #endif
    }

}

extension Int {
    func asTimeString() -> String {
        let s = self % 60
        let m = (self / 60) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
