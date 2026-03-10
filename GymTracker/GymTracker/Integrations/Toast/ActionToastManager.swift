import SwiftUI
import Combine

@MainActor
class ActionToastManager: ObservableObject {
    @Published var toasts: [ActionToast] = []
    private var activeTimerTask: Task<Void, Never>?
    private var remainingTimes: [UUID: TimeInterval] = [:]

    /// The front (newest) toast — the only one whose timer is active.
    var frontToast: ActionToast? { toasts.last }

    @Published var isDragging: Bool = false

    // MARK: - Public API

    /// Pause the front timer (e.g. user is dragging).
    func pauseTimer() {
        activeTimerTask?.cancel()
        activeTimerTask = nil
    }

    /// Resume the front timer after a drag ends.
    func resumeTimer() {
        restartFrontTimer()
    }

    func add(
        message: String,
        intent: ActionIntent = .notification,
        actionTitle: String? = nil,
        timeout: TimeInterval = 4,
        onAction: (() -> Void)? = nil,
        onTimeout: (() -> Void)? = nil
    ) {
        let toast = ActionToast(
            message: message,
            intent: intent,
            actionTitle: actionTitle,
            timeout: timeout,
            onAction: onAction,
            onTimeout: onTimeout
        )
        remainingTimes[toast.id] = timeout
        toasts.append(toast)
        restartFrontTimer()
    }

    /// Called when user taps the action button or swipes left — triggers the toast's action callback.
    func executeAction(id: UUID) {
        guard let toast = toasts.first(where: { $0.id == id }) else { return }
        toast.onAction?()
        toasts.removeAll { $0.id == id }
        remainingTimes.removeValue(forKey: id)
        restartFrontTimer()
    }

    /// Called when user swipes a toast away — deletion stays (same as timeout).
    func expireToast(id: UUID) {
        guard let toast = toasts.first(where: { $0.id == id }) else { return }
        toast.onTimeout?()
        toasts.removeAll { $0.id == id }
        remainingTimes.removeValue(forKey: id)
        restartFrontTimer()
    }

    /// Called when user swipes up — dismiss all toasts as timeouts.
    func dismissAll() {
        activeTimerTask?.cancel()
        activeTimerTask = nil
        for toast in toasts {
            toast.onTimeout?()
        }
        toasts.removeAll()
        remainingTimes.removeAll()
    }

    // MARK: - Private

    /// Called when the front toast's timer fires.
    private func expire(id: UUID) {
        guard let toast = toasts.first(where: { $0.id == id }) else { return }
        toast.onTimeout?()
        toasts.removeAll { $0.id == id }
        remainingTimes.removeValue(forKey: id)
        restartFrontTimer()
    }

    /// Cancels any running timer and starts a new one for the current front toast.
    /// Only the front toast's timer ticks — all others are paused.
    private func restartFrontTimer() {
        activeTimerTask?.cancel()
        activeTimerTask = nil

        guard let front = frontToast else { return }
        guard let remaining = remainingTimes[front.id], remaining > 0 else {
            expire(id: front.id)
            return
        }

        let frontId = front.id
        activeTimerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.expire(id: frontId)
        }
    }
}
