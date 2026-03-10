//
//  WatchSessionManager.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-12-09.
//

import Swift
import Combine
import Foundation
#if os(iOS)
import WatchConnectivity

#endif

final class WatchSessionManager: NSObject, WCSessionDelegate, ObservableObject {
    
    private let timerService: TimerService
//    private let exerciseService: ExerciseService
    private var cancellables = Set<AnyCancellable>()
    
    init(timerService: TimerService) {
        self.timerService = timerService
//        self.exerciseService = exerciseService
        super.init()
        activate()
        observeServices()
    }
        
    private func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
    
    private func observeServices() {
        timerService.$timer
            .receive(on: DispatchQueue.main)
            .sink { [weak self] timer in
                // Only send if watch is reachable
                guard WCSession.default.isReachable else { 
                    print("Watch not reachable, skipping timer update")
                    return 
                }
                if let timer = timer {
                    // Timer exists - send update
                    guard let encoded = try? JSONEncoder().encode(timer.toDTO()) else { return }
                    self?.send(data: encoded, type: "timerUpdate")
                } else {
                    // Timer was deleted/cleared - notify watch
                    self?.send(["action": "timerCleared"])
                }
            }
            .store(in: &cancellables)
        
        timerService.$pendingLength
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (_ : Int) in
                // Send update to watch when pending length changes
                guard WCSession.default.isReachable else { 
                    print("Watch not reachable, skipping pending length update")
                    return 
                }
                self?.send(["action": "updatePendingLength", "length": self?.timerService.pendingLength ?? 0])
            }
            .store(in: &cancellables)
    }

    
    func send(_ message: [String: Any]) {
        WCSession.default.sendMessage(message, replyHandler: nil)
    }

    func send(data: Data, type: String) {
        WCSession.default.sendMessageData(data, replyHandler: nil, errorHandler: { error in
            print("Failed to send \(type) to watch:", error)
        })
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        print("iPhone session activated: \(activationState.rawValue), error: \(String(describing: error))")
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String : Any],
        replyHandler: @escaping ([String : Any]) -> Void = { _ in }
    ) {
        guard let action = message["action"] as? String else { return }
        switch action {

        case "requestInitialState":
            if let timer = timerService.timer {
                if let encoded = try? JSONEncoder().encode(timer.toDTO()) {
                    replyHandler(["timer": encoded, "pendingLength": timerService.pendingLength])
                } else {
                    replyHandler(["timer": NSNull(), "pendingLength": timerService.pendingLength])
                }
            } else {
                replyHandler(["timer": NSNull(), "pendingLength": timerService.pendingLength])
            }

        case "requestTimer":
            if let timer = timerService.timer {
                if let encoded = try? JSONEncoder().encode(timer.toDTO()) {
                    replyHandler(["timer": encoded])
                } else {
                    replyHandler(["timer": NSNull()])
                }
            }

        case "startTimer":
            if let length = message["length"] as? Int {
                timerService.pendingLength = length
            }
            timerService.start()

        case "pauseTimer":
            timerService.pause()

        case "resumeTimer":
            timerService.resume()

        case "stopTimer":
            timerService.stop(delete: message["delete"] as? Bool ?? false)

        case "updatePendingLength":
            if let length = message["length"] as? Int {
                timerService.pendingLength = length
            }

        default:
            break
        }
    }
    
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        // Called when the session is switching to another device
        print("iPhone WCSession did become inactive")
    }

    func sessionDidDeactivate(_ session: WCSession) {
        // Must reactivate after deactivation
        print("iPhone WCSession deactivated, reactivating")
        WCSession.default.activate()
    }
}
