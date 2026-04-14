//
//  WatchSessionListener.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-12-09.
//

// GymTrackerWatch Watch App
// WatchSessionManager.swift

import WatchConnectivity
import Combine

final class WatchSessionListener: NSObject, ObservableObject, WCSessionDelegate {
    @Published var timer: WatchTimerSnapshot?
    
    @Published var isReachable: Bool = false
    @Published var pendingLength: Int = 0
    @Published var wasPaused: Bool = false

    override init() {
        super.init()
        activate()
    }

    // WCSession Setup
    private func activate() {
        guard WCSession.isSupported() else { 
            print("WCSession not supported on this device")
            return 
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        print("Watch WCSession activated")
    }

    // Called when session is ready on watch
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if activationState == .activated {
            Task {
                isReachable = session.isReachable
            }
            requestInitialState()
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        Task {
            isReachable = session.isReachable
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        applyStateUpdate(from: applicationContext)
    }

    // Public API (used by watch views)
    func requestInitialState() {
        guard WCSession.default.isReachable else { return }

        WCSession.default.sendMessage(
            ["action": "requestInitialState"],
            replyHandler: { [weak self] reply in
                self?.handleInitialState(reply: reply)
            },
            errorHandler: { error in
                print("requestInitialState error:", error)
            }
        )
    }
    
    func startTimer(length: Int? = nil) {
        var payload: [String: Any] = ["action": "startTimer"]
        if let length { payload["length"] = length }

        WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: { error in
            print("startTimer error:", error)
        })
    }
    
    func pauseTimer() {
        WCSession.default.sendMessage(["action": "pauseTimer"], replyHandler: nil, errorHandler: { error in
            print("pauseTimer error:", error)
        })
    }

    func resumeTimer() {
        WCSession.default.sendMessage(["action": "resumeTimer"], replyHandler: nil, errorHandler: { error in
            print("resumeTimer error:", error)
        })
    }

    func stopTimer(delete: Bool = false) {
        guard WCSession.default.isReachable else {
            print("iPhone not reachable, cannot stop timer")
            return
        }
        WCSession.default.sendMessage(
            ["action": "stopTimer", "delete": delete],
            replyHandler: nil,
            errorHandler: { error in
                print("stopTimer error:", error)
            }
        )
    }
    
    func addToTimer(seconds: Int) {
       self.pendingLength += seconds
        WCSession.default.sendMessage(
            ["action": "updatePendingLength", "length": pendingLength],
            replyHandler: nil,
            errorHandler: { error in
                print("updatePendingLength error:", error)
            }
        )
    }
    // Incoming messages (push updates from iPhone)
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        if let action = message["action"] as? String {
            switch action {
            case "timerCleared":
                DispatchQueue.main.async {
                    self.timer = nil
                    // self.pendingLength = 0
                }
            case "updatePendingLength":
                if let length = message["length"] as? Int {
                    DispatchQueue.main.async {
                        self.pendingLength = length
                    }
                }
            default:
                break
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        // For binary DTO updates (e.g. timerUpdate, exerciseUpdate, etc.)
        do {
            let dto = try JSONDecoder().decode(WatchTimerSnapshot.self, from: messageData)
            DispatchQueue.main.async {
                self.timer = dto
            }
        } catch {
            print("Failed to decode timer update:", error)
        }
    }

    // Reply handlers

    private func handleInitialState(reply: [String: Any]) {
        applyStateUpdate(from: reply)
    }

    private func applyStateUpdate(from payload: [String: Any]) {
        if let timerData = payload["timer"] as? Data,
           let dto = try? JSONDecoder().decode(WatchTimerSnapshot.self, from: timerData) {
            DispatchQueue.main.async {
                self.timer = dto
                if !dto.isPaused {
                    self.wasPaused = false
                }
            }
        } else if payload["timer"] is NSNull {
            DispatchQueue.main.async {
                self.timer = nil
            }
        }

        if let pendingLength = payload["pendingLength"] as? Int {
            DispatchQueue.main.async {
                self.pendingLength = pendingLength
            }
        }

        if let timer = self.timer, !timer.isPaused {
            self.wasPaused = false
        }
    }
}
