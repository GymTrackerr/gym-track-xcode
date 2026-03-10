import SwiftUI

// MARK: - Action Intent

enum ActionIntent {
    case undo
    case notification
    case custom(title: String, icon: String)

    var defaultTitle: String {
        switch self {
        case .undo:                  return "Undo"
        case .notification:          return "OK"
        case .custom(let title, _):  return title
        }
    }

    var icon: String {
        switch self {
        case .undo:                  return "arrow.uturn.left"
        case .notification:          return "checkmark"
        case .custom(_, let icon):   return icon
        }
    }
}

// MARK: - Toast Model

struct ActionToast: Identifiable {
    let id = UUID()
    let message: String
    let intent: ActionIntent
    let actionTitle: String
    let timeout: TimeInterval
    let onAction: (() -> Void)?
    let onTimeout: (() -> Void)?

    init(
        message: String,
        intent: ActionIntent = .notification,
        actionTitle: String? = nil,
        timeout: TimeInterval = 4,
        onAction: (() -> Void)? = nil,
        onTimeout: (() -> Void)? = nil
    ) {
        self.message = message
        self.intent = intent
        self.actionTitle = actionTitle ?? intent.defaultTitle
        self.timeout = timeout
        self.onAction = onAction
        self.onTimeout = onTimeout
    }
}

// MARK: - Toast Stack View

struct ActionToastStack: View {
    @EnvironmentObject var toastManager: ActionToastManager
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var dragAxis: DragAxis = .undecided

    private enum DragAxis {
        case undecided, horizontal, vertical
    }

    var body: some View {
        if !toastManager.toasts.isEmpty {
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    // Background toasts (older, stacked behind)
                    let backgroundToasts = Array(toastManager.toasts.dropLast().suffix(2))
                    ForEach(Array(backgroundToasts.enumerated()), id: \.element.id) { index, toast in
                        let depth = backgroundToasts.count - index
                        toastRow(toast, isFront: false)
                            .scaleEffect(1.0 - Double(depth) * 0.05)
                            .opacity(1.0 - Double(depth) * 0.25)
                            .offset(y: -CGFloat(depth) * 6)
                    }

                    // Front toast
                    if let front = toastManager.frontToast {
                        frontToastView(front)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 6)

                // Shadow gradient below toasts
                LinearGradient(
                    colors: [.black.opacity(0.12), .black.opacity(0.05), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 20)
                .allowsHitTesting(false)
            }
            .animation(.easeInOut(duration: 0.25), value: toastManager.toasts.map(\.id))
        }
    }

    // MARK: - Front Toast with Gesture + Icons

    @ViewBuilder
    private func frontToastView(_ front: ActionToast) -> some View {
        let horizontalDrag = dragAxis == .horizontal ? dampened(dragOffset.width, limit: 200) : 0
        let verticalDrag = dragAxis == .vertical ? min(dampened(dragOffset.height, limit: 160), 0) : 0

        // Swipe progress for icons (0...1)
        let leftProgress = min(max(-dragOffset.width, 0) / 80.0, 1.0)
        let rightProgress = min(max(dragOffset.width, 0) / 80.0, 1.0)
        let upProgress = min(max(-dragOffset.height, 0) / 50.0, 1.0)

        toastRow(front, isFront: true)
            // Left icon: action (swipe left = execute action)
            .overlay(alignment: .leading) {
                Image(systemName: front.intent.icon)
                    .font(.body.weight(.bold))
                    .foregroundStyle(.tint)
                    .opacity(dragAxis == .horizontal ? leftProgress : 0)
                    .scaleEffect(0.6 + leftProgress * 0.4)
                    .offset(x: -28 - leftProgress * 6)
            }
            // Right icon: dismiss (swipe right = expire)
            .overlay(alignment: .trailing) {
                Image(systemName: "xmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.secondary)
                    .opacity(dragAxis == .horizontal ? rightProgress : 0)
                    .scaleEffect(0.6 + rightProgress * 0.4)
                    .offset(x: 28 + rightProgress * 6)
            }
            // Top icon: clear all (swipe up)
            .overlay(alignment: .top) {
                Image(systemName: "chevron.up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.secondary)
                    .opacity(dragAxis == .vertical ? upProgress : 0)
                    .scaleEffect(0.6 + upProgress * 0.4)
                    .offset(y: -22 - upProgress * 4)
            }
            .offset(x: horizontalDrag, y: verticalDrag)
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            toastManager.pauseTimer()
                        }
                        if dragAxis == .undecided {
                            let h = abs(value.translation.width)
                            let v = abs(value.translation.height)
                            if max(h, v) > 10 {
                                dragAxis = h > v ? .horizontal : .vertical
                            }
                        }
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        isDragging = false
                        handleSwipeEnd(value, frontId: front.id)
                        dragAxis = .undecided
                    }
            )
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.85), value: dragOffset)
    }

    // MARK: - Helpers

    private func dampened(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        let sign: CGFloat = value < 0 ? -1 : 1
        let mag = abs(value)
        return sign * limit * log2(1 + mag / limit)
    }

    private func handleSwipeEnd(_ value: DragGesture.Value, frontId: UUID) {
        let horizontal = value.translation.width
        let vertical = value.translation.height

        // Swipe up — dismiss ALL
        if dragAxis == .vertical && vertical < -50 {
            withAnimation(.easeOut(duration: 0.2)) {
                dragOffset = CGSize(width: 0, height: -300)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                toastManager.dismissAll()
                dragOffset = .zero
            }
            return
        }

        // Swipe left — execute action
        if dragAxis == .horizontal && horizontal < -80 {
            withAnimation(.easeOut(duration: 0.2)) {
                dragOffset = CGSize(width: -400, height: 0)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                toastManager.executeAction(id: frontId)
                dragOffset = .zero
            }
            return
        }

        // Swipe right — dismiss
        if dragAxis == .horizontal && horizontal > 80 {
            withAnimation(.easeOut(duration: 0.2)) {
                dragOffset = CGSize(width: 400, height: 0)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                toastManager.expireToast(id: frontId)
                dragOffset = .zero
            }
            return
        }

        // Below threshold — snap back
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            dragOffset = .zero
        }
        toastManager.resumeTimer()
    }

    // MARK: - Toast Row

    @ViewBuilder
    private func toastRow(_ toast: ActionToast, isFront: Bool) -> some View {
        HStack(spacing: 10) {
            Text(toast.message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if toast.onAction != nil {
                Button {
                    toastManager.executeAction(id: toast.id)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: toast.intent.icon)
                        Text(toast.actionTitle)
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.thinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(isFront ? 0.15 : 0.08), radius: isFront ? 8 : 4, x: 0, y: 3)
    }
}
