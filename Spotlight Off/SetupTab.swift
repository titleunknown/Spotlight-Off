import SwiftUI

/// The setup checklist. Each step shows live status, rechecked whenever a
/// window becomes key (e.g. after returning from System Settings).
struct SetupTab: View {
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject private var notifier = Notifier.shared

    @State private var hasFullDiskAccess = FullDiskAccess.isGranted
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginNeedsApproval = LaunchAtLogin.needsApproval

    private var notificationsAllowed: Bool {
        notifier.systemAuthorization == .authorized || notifier.systemAuthorization == .provisional
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader("Get Set Up")

                Card {
                    SetupStep(
                        number: 1, title: "Grant Full Disk Access", isDone: hasFullDiskAccess,
                        doneText: "Granted", pendingText: "Required",
                        detail: "Spotlight Off needs Full Disk Access to turn off Spotlight on your drives — without it, nothing happens when you connect one. In System Settings, switch on Spotlight Off. If it isn't listed, click + and add it from your Applications folder.") {
                        Button("Open Full Disk Access Settings") { FullDiskAccess.openSettings() }
                    }

                    RowDivider()

                    SetupStep(
                        number: 2, title: "Launch at Login", isDone: launchAtLogin,
                        doneText: "On", pendingText: loginNeedsApproval ? "Needs approval" : "Recommended",
                        detail: "Keeps Spotlight Off running in the background so every drive is handled, including ones connected when your Mac starts up.") {
                        if loginNeedsApproval {
                            Button("Open Login Items Settings") { NSWorkspace.shared.open(LaunchAtLogin.settingsURL) }
                        } else if !launchAtLogin {
                            Button("Turn On") { launchAtLogin = LaunchAtLogin.set(true); refresh() }
                        }
                    }

                    RowDivider()

                    SetupStep(
                        number: 3, title: "Allow Notifications", isDone: notificationsAllowed,
                        doneText: "Allowed", pendingText: "Optional",
                        detail: "Shows a macOS notification when a drive is handled. If you'd rather not allow them, Spotlight Off uses its own pop-up instead — or turn drive notifications off in the Settings tab.") {
                        switch notifier.systemAuthorization {
                        case .notDetermined:
                            Button("Allow…") { notifier.requestAuthorizationIfNeeded() }
                        case .denied:
                            Button("Open Notification Settings") { notifier.openSystemNotificationSettings() }
                        default:
                            EmptyView()
                        }
                    }

                    RowDivider()

                    SetupStep(
                        number: 4, title: "Connect a Drive", isDone: hasFullDiskAccess,
                        doneText: "Ready", pendingText: "Waiting on step 1",
                        detail: "That's it. When you connect an external drive or SD card, Spotlight Off turns its indexing off automatically — no password prompt. Connected drives and their status appear in the Drives tab.") {
                        Button("How Spotlight Off Works") { navigation.tab = .help }
                    }
                }

                SectionHeader("Support Development")

                VStack(alignment: .leading, spacing: 10) {
                    Text("Spotlight Off is free, open source and CC BY-NC 4.0 licensed. If it saves you time, consider supporting development.")
                        .font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        DonateButton(label: "PayPal", icon: "💳",
                                     url: "https://www.paypal.com/donate/?hosted_button_id=AEY7AC82BKH5C",
                                     color: Color(red: 0.0, green: 0.47, blue: 0.75))
                        DonateButton(label: "Venmo", icon: "✦",
                                     url: "https://account.venmo.com/u/FAINI",
                                     color: Color(red: 0.22, green: 0.72, blue: 0.60))
                        DonateButton(label: "Coffee", icon: "☕",
                                     url: "https://buymeacoffee.com/fainimade",
                                     color: Color(red: 0.85, green: 0.6, blue: 0.0))
                    }
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 20)
            }
            .padding(.top, 8)
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            refresh()
        }
    }

    private func refresh() {
        hasFullDiskAccess = FullDiskAccess.isGranted
        launchAtLogin = LaunchAtLogin.isEnabled
        loginNeedsApproval = LaunchAtLogin.needsApproval
        Task { await notifier.refreshAuthorization() }
    }
}

// MARK: - Setup Step

struct SetupStep<Action: View>: View {
    let number: Int
    let title: String
    let isDone: Bool
    let doneText: String
    let pendingText: String
    let detail: String
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(isDone ? Color.green : Color.accentColor.opacity(0.85))
                    .frame(width: 24, height: 24)
                if isDone {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                } else {
                    Text("\(number)").font(.system(size: 11, weight: .bold))
                }
            }
            .foregroundColor(.white)
            .animation(.easeInOut(duration: 0.3), value: isDone)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(isDone ? doneText : pendingText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isDone ? .green : .orange)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill((isDone ? Color.green : Color.orange).opacity(0.15)))
                }
                Text(detail)
                    .font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                action()
                    .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }
}

// MARK: - Donate Button

struct DonateButton: View {
    let label: String; let icon: String; let url: String; let color: Color
    @State private var hovered = false

    var body: some View {
        Button(action: { if let u = URL(string: url) { NSWorkspace.shared.open(u) } }) {
            HStack(spacing: 6) {
                Text(icon).font(.system(size: 13))
                Text(label).font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(hovered ? .white : color)
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(hovered ? color.opacity(0.85) : color.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(color.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain).onHover { hovered = $0 }
    }
}
