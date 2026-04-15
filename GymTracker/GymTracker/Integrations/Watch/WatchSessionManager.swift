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

final class WatchSessionManager: NSObject, WCSessionDelegate, ObservableObject {
    private let timerController: any WatchTimerControlling
    private var cancellables = Set<AnyCancellable>()

    init(timerController: any WatchTimerControlling) {
        self.timerController = timerController
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
        timerController.timerPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] timer in
                defer { self?.pushApplicationContext() }

                // Only send if watch is reachable
                guard WCSession.default.isReachable else { 
                    print("Watch not reachable, skipping timer update")
                    return 
                }
                if let timer = timer {
                    // Timer exists - send update
                    guard let encoded = try? JSONEncoder().encode(timer) else { return }
                    self?.send(data: encoded, type: "timerUpdate")
                } else {
                    // Timer was deleted/cleared - notify watch
                    self?.send(["action": "timerCleared"])
                }
            }
            .store(in: &cancellables)

        timerController.pendingLengthPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (_ : Int) in
                // Send update to watch when pending length changes
                guard WCSession.default.isReachable else { 
                    print("Watch not reachable, skipping pending length update")
                    self?.pushApplicationContext()
                    return
                }
                self?.send(["action": "updatePendingLength", "length": self?.timerController.pendingLength ?? 0])
                self?.pushApplicationContext()
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

    private func pushApplicationContext() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        do {
            try session.updateApplicationContext(currentApplicationContext())
        } catch {
            print("Failed to update watch application context:", error)
        }
    }

    private func currentApplicationContext() -> [String: Any] {
        var context: [String: Any] = [
            "pendingLength": timerController.pendingLength,
            "sentAt": Date().timeIntervalSince1970,
        ]

        if let timer = timerController.timerSnapshot,
           let encoded = try? JSONEncoder().encode(timer) {
            context["timer"] = encoded
        } else {
            context["timer"] = NSNull()
        }

        return context
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        print("iPhone session activated: \(activationState.rawValue), error: \(String(describing: error))")
        guard activationState == .activated else { return }
        pushApplicationContext()
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String : Any],
        replyHandler: @escaping ([String : Any]) -> Void = { _ in }
    ) {
        guard let action = message["action"] as? String else { return }
        switch action {

        case "requestInitialState":
            if let timer = timerController.timerSnapshot {
                if let encoded = try? JSONEncoder().encode(timer) {
                    replyHandler(["timer": encoded, "pendingLength": timerController.pendingLength])
                } else {
                    replyHandler(["timer": NSNull(), "pendingLength": timerController.pendingLength])
                }
            } else {
                replyHandler(["timer": NSNull(), "pendingLength": timerController.pendingLength])
            }

        case "requestTimer":
            if let timer = timerController.timerSnapshot {
                if let encoded = try? JSONEncoder().encode(timer) {
                    replyHandler(["timer": encoded])
                } else {
                    replyHandler(["timer": NSNull()])
                }
            }

        case "startTimer":
            timerController.start(length: message["length"] as? Int)

        case "pauseTimer":
            timerController.pause()

        case "resumeTimer":
            timerController.resume()

        case "stopTimer":
            timerController.stop(delete: message["delete"] as? Bool ?? false)

        case "updatePendingLength":
            if let length = message["length"] as? Int {
                timerController.pendingLength = length
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
#endif
