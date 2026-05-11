import Foundation

enum SessionIntentHandoff {
    static let didRequestActiveSession = Notification.Name("SessionIntentHandoff.didRequestActiveSession")

    private static let pendingActiveSessionIdKey = "session.intent.pendingActiveSessionId"

    static func requestActiveSession(sessionId: UUID) {
        UserDefaults(suiteName: SharedModelConfig.appGroupIdentifier)?
            .set(sessionId.uuidString, forKey: pendingActiveSessionIdKey)
        NotificationCenter.default.post(name: didRequestActiveSession, object: sessionId)
    }

    static func consumePendingActiveSessionId() -> UUID? {
        guard let defaults = UserDefaults(suiteName: SharedModelConfig.appGroupIdentifier),
              let rawValue = defaults.string(forKey: pendingActiveSessionIdKey),
              let sessionId = UUID(uuidString: rawValue) else {
            return nil
        }

        defaults.removeObject(forKey: pendingActiveSessionIdKey)
        return sessionId
    }
}
