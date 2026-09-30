import AppKit
import SwiftUI
import UserNotifications

struct Notice: Sendable {
    enum Kind: Sendable { case success, info, failure }

    let title: String
    let subtitle: String
    let kind: Kind
    /// Opened when a system notification is clicked.
    var url: URL? = nil
    /// Drive notices respect "Show drive notifications"; update notices don't.
    var isDriveEvent = true
}

/// Delivers notices as system notifications (which respect Focus and land in
/// Notification Center) or as the built-in pop-up. Falls back to the pop-up
/// when system notifications aren't allowed for the app.
@MainActor
final class Notifier: ObservableObject {
    static let shared = Notifier()

    @Published private(set) var systemAuthorization: UNAuthorizationStatus = .notDetermined

    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    var style: NotificationStyle {
        NotificationStyle(rawValue: UserDefaults.standard.string(forKey: PrefKey.notificationStyle) ?? "") ?? .system
    }

    private var systemAllowed: Bool {
        systemAuthorization == .authorized || systemAuthorization == .provisional
    }

    func post(_ notice: Notice) {
        if notice.isDriveEvent && !UserDefaults.standard.bool(forKey: PrefKey.notificationsEnabled) { return }
        if style == .system && systemAllowed {
            postSystem(notice)
        } else {
            presentToast(notice)
        }
    }

    /// Asks for permission the first time system notifications are in use.
    func requestAuthorizationIfNeeded() {
        Task {
            let center = UNUserNotificationCenter.current()
            if style == .system, await center.notificationSettings().authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            await refreshAuthorization()
        }
    }

    func refreshAuthorization() async {
        #if DEBUG
        if ScreenshotMode.isActive { systemAuthorization = .authorized; return }
        #endif
        systemAuthorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func openSystemNotificationSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - System Notifications

    private func postSystem(_ notice: Notice) {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.subtitle
        if let url = notice.url { content.userInfo = ["url": url.absoluteString] }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                LogStore.shared.log("Notification error: \(error.localizedDescription)", kind: .failure)
            }
        }
    }

    // MARK: - Pop-up

    private func presentToast(_ notice: Notice) {
        hideTask?.cancel()
        panel?.close()

        let (icon, color): (String, NSColor) = {
            switch notice.kind {
            case .success: return ("checkmark.circle.fill", .systemGreen)
            case .info:    return ("info.circle.fill", .systemBlue)
            case .failure: return ("xmark.circle.fill", .systemRed)
            }
        }()

        let hostingView = NSHostingView(rootView: ToastView(
            icon: icon, title: notice.title, subtitle: notice.subtitle, iconColor: Color(color)
        ))
        hostingView.frame = NSRect(x: 0, y: 0, width: 280, height: 64)

        let p = NSPanel(
            contentRect: hostingView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        p.contentView = hostingView
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .stationary]
        p.isMovable = false
        p.ignoresMouseEvents = true

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let margin: CGFloat = 16
            p.setFrameOrigin(NSPoint(x: frame.maxX - hostingView.frame.width - margin,
                                     y: frame.maxY - hostingView.frame.height - margin))
        }

        p.alphaValue = 0
        p.orderFrontRegardless()
        panel = p

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            p.animator().alphaValue = 1
        }

        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func dismiss() {
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            p.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                p.close()
                // A newer toast may have replaced this one during the fade-out.
                if self.panel === p { self.panel = nil }
            }
        })
    }
}

// MARK: - Toast View

struct ToastView: View {
    let icon: String
    let title: String
    let subtitle: String
    let iconColor: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 280, height: 64)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 4)
        )
        .padding(6)
    }
}
