import SwiftUI

// MARK: - Settings View (Tabbed)

enum SettingsTab { case settings, drives, log, setup, help }

/// Which settings tab is showing — shared so the menu bar can open the window
/// straight to a tab (e.g. Setup when Full Disk Access is missing).
@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var tab: SettingsTab = .settings
}

struct SettingsView: View {
    @ObservedObject var monitor: DriveMonitor
    @ObservedObject var updater: UpdateChecker
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────────────────
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "externaldrive.badge.xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.accentColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spotlight Off").font(.headline)
                    Text("Automatically disables Spotlight indexing on external drives")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Text("Version \(AppInfo.version)")
                    .font(.caption).foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)

            Divider()

            // ── Tab Picker ───────────────────────────────────────────────────
            HStack(spacing: 0) {
                TabButton(title: "Settings", systemImage: "gearshape", tab: .settings, selected: $navigation.tab)
                TabButton(title: "Drives", systemImage: "externaldrive", tab: .drives, selected: $navigation.tab)
                TabButton(title: "Activity Log", systemImage: "list.bullet.rectangle", tab: .log, selected: $navigation.tab)
                TabButton(title: "Setup", systemImage: "checklist", tab: .setup, selected: $navigation.tab)
                TabButton(title: "Help", systemImage: "questionmark.circle", tab: .help, selected: $navigation.tab)
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 4)

            Divider()

            // ── Tab Content ──────────────────────────────────────────────────
            Group {
                switch navigation.tab {
                case .settings: GeneralTab(updater: updater)
                case .drives:   DrivesTab(monitor: monitor)
                case .log:      ActivityLogTab()
                case .setup:    SetupTab(navigation: navigation)
                case .help:     HelpTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // ── Footer ───────────────────────────────────────────────────────
            HStack(spacing: 4) {
                Text("By").font(.caption2).foregroundColor(.secondary.opacity(0.5))
                Button("FAINI MADE") { NSWorkspace.shared.open(URL(string: "https://www.fainimade.com")!) }
                    .buttonStyle(.plain).font(.caption2).fontWeight(.semibold)
                    .foregroundColor(.secondary.opacity(0.7))
                Text("·").font(.caption2).foregroundColor(.secondary.opacity(0.3))
                Button("GitHub") { NSWorkspace.shared.open(URL(string: "https://github.com/titleunknown/Spotlight-Off")!) }
                    .buttonStyle(.plain).font(.caption2).foregroundColor(.secondary.opacity(0.5))
                Text("·").font(.caption2).foregroundColor(.secondary.opacity(0.3))
                Button("CC BY-NC 4.0") { NSWorkspace.shared.open(URL(string: "https://github.com/titleunknown/Spotlight-Off/blob/main/LICENSE")!) }
                    .buttonStyle(.plain).font(.caption2).foregroundColor(.secondary.opacity(0.5))
                Spacer()
                Text("Full Disk Access required").font(.caption2).foregroundColor(.secondary.opacity(0.4))
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
        .frame(width: 500, height: 640)
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let title: String
    let systemImage: String
    let tab: SettingsTab
    @Binding var selected: SettingsTab

    var isSelected: Bool { selected == tab }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { selected = tab }
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings Tab

struct GeneralTab: View {
    @ObservedObject var updater: UpdateChecker
    @ObservedObject private var notifier = Notifier.shared

    @State private var launchAtLogin: Bool = LaunchAtLogin.isEnabled
    @State private var preventDSStore = FinderPrefs.preventsDSStoreOnExternalDrives
    @State private var finderNeedsRelaunch = false
    @AppStorage(PrefKey.notificationsEnabled) private var notificationsEnabled = true
    @AppStorage(PrefKey.notificationStyle) private var notificationStyle: NotificationStyle = .system
    @AppStorage(PrefKey.autoCheckUpdates) private var autoCheckUpdates = true
    @AppStorage(PrefKey.removeIndexOnDisable) private var removeIndexOnDisable = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FullDiskAccessBanner()

                // ── Settings Section ─────────────────────────────────────────
                SectionHeader("Settings")

                Card {
                    SettingsRow(icon: "arrow.up.circle", iconColor: .blue) {
                        Toggle("Launch at login", isOn: $launchAtLogin)
                            .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                    }

                    RowDivider()

                    SettingsRow(icon: "bell", iconColor: .orange) {
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Show drive notifications", isOn: $notificationsEnabled)
                            if notificationsEnabled {
                                Picker("Style", selection: $notificationStyle) {
                                    ForEach(NotificationStyle.allCases) { Text($0.label).tag($0) }
                                }
                                .pickerStyle(.segmented).fixedSize()
                                .onChange(of: notificationStyle) { _, _ in notifier.requestAuthorizationIfNeeded() }
                                if notificationStyle == .system { systemNotificationHint }
                            }
                        }
                    }

                    RowDivider()

                    SettingsRow(icon: "trash", iconColor: .red) {
                        VStack(alignment: .leading, spacing: 2) {
                            Toggle("Also remove the existing Spotlight index", isOn: $removeIndexOnDisable)
                            Caption("Deletes the .Spotlight-V100 folder macOS already built on a drive, freeing its space.")
                        }
                    }

                    RowDivider()

                    SettingsRow(icon: "doc.badge.gearshape", iconColor: .gray) {
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Stop Finder creating .DS_Store files on external drives", isOn: $preventDSStore)
                                .onChange(of: preventDSStore) { _, enabled in
                                    guard enabled != FinderPrefs.preventsDSStoreOnExternalDrives else { return }
                                    FinderPrefs.preventsDSStoreOnExternalDrives = enabled
                                    LogStore.shared.log(enabled ? "Finder will stop writing .DS_Store files on external drives"
                                                                : "Finder may write .DS_Store files on external drives again")
                                    finderNeedsRelaunch = true
                                }
                            HStack(spacing: 8) {
                                Caption("A Finder setting. Takes effect after Finder relaunches.")
                                if finderNeedsRelaunch {
                                    Button("Relaunch Finder") {
                                        FinderPrefs.relaunchFinder()
                                        finderNeedsRelaunch = false
                                    }
                                    .buttonStyle(.link).font(.caption)
                                }
                            }
                        }
                    }

                    RowDivider()

                    SettingsRow(icon: "arrow.triangle.2.circlepath", iconColor: .purple) {
                        VStack(alignment: .leading, spacing: 6) {
                            updateRow
                            Toggle("Check automatically once a day", isOn: $autoCheckUpdates)
                                .controlSize(.small)
                        }
                    }
                }


                Spacer(minLength: 20)
            }
            .padding(.top, 8)
        }
        // The settings window is reused, so resync with system state (login
        // item, notification permission, Finder setting) whenever it's shown
        // or a window becomes key.
        .onAppear(perform: syncWithSystem)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            syncWithSystem()
        }
    }

    @ViewBuilder
    private var systemNotificationHint: some View {
        switch notifier.systemAuthorization {
        case .denied:
            HStack(spacing: 6) {
                Caption("Notifications are off for Spotlight Off in System Settings, so pop-ups are used instead.")
                Button("Open") { notifier.openSystemNotificationSettings() }
                    .buttonStyle(.link).font(.caption)
            }
        case .notDetermined:
            HStack(spacing: 6) {
                Caption("Pop-ups are used until you allow notifications.")
                Button("Allow…") { notifier.requestAuthorizationIfNeeded() }
                    .buttonStyle(.link).font(.caption)
            }
        default:
            EmptyView()
        }
    }

    private var updateRow: some View {
        HStack {
            switch updater.state {
            case .idle:        Text("Check for Updates")
            case .checking:    Text("Checking…").foregroundColor(.secondary)
            case .upToDate:    Text("You're up to date ✓").foregroundColor(.green)
            case .updateAvailable(let tag, _):
                Text("Update available: \(tag)").foregroundColor(.orange)
            case .error(let msg):
                Text("Error: \(msg)").foregroundColor(.red).lineLimit(2)
            }
            Spacer()
            if case .updateAvailable(_, let url) = updater.state {
                Button("Download") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            } else {
                Button(updater.isChecking ? "Checking…" : "Check Now") { updater.check() }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(updater.isChecking)
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        // Skip when the toggle already matches reality — this fires again when
        // we revert the value below, and acting on that echo would unregister
        // what the user just registered.
        guard enabled != LaunchAtLogin.isEnabled else { return }
        launchAtLogin = LaunchAtLogin.set(enabled)
    }

    private func syncWithSystem() {
        launchAtLogin = LaunchAtLogin.isEnabled
        preventDSStore = FinderPrefs.preventsDSStoreOnExternalDrives
        Task { await notifier.refreshAuthorization() }
    }
}

// MARK: - Drives Tab

struct DrivesTab: View {
    @ObservedObject var monitor: DriveMonitor

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium; f.timeStyle = .short
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FullDiskAccessBanner()

                // ── Connected Drives Section ─────────────────────────────────
                HStack {
                    SectionHeader("Connected Drives")
                    Spacer()
                    Button {
                        monitor.refreshVolumes()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption).fontWeight(.semibold)
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.accentColor)
                    .disabled(monitor.isScanningVolumes)
                    .help("Rescan connected drives")
                    .padding(.top, 20).padding(.trailing, 20)
                }

                if monitor.connectedDrives.isEmpty {
                    EmptyState(
                        icon: monitor.isScanningVolumes ? nil : "externaldrive",
                        title: monitor.isScanningVolumes ? "Scanning drives…" : "No external drives connected",
                        detail: monitor.isScanningVolumes ? nil : "Connected drives appear here with their Spotlight status.")
                } else {
                    Card {
                        ForEach(Array(monitor.connectedDrives.enumerated()), id: \.element.id) { index, volume in
                            if index > 0 { RowDivider() }
                            DriveRow(volume: volume,
                                     isAllowed: volume.uuid.map(monitor.isAllowed) ?? false,
                                     isBusy: monitor.busyPaths.contains(volume.path),
                                     monitor: monitor)
                        }
                    }
                    Caption("Re-enable keeps Spotlight on for that drive. More actions are in the ⋯ menu.")
                        .padding(.horizontal, 20).padding(.top, 4)
                }

                // ── Allowed Drives Section ───────────────────────────────────
                if !monitor.allowedVolumes.isEmpty {
                    SectionHeader("Allowed to Index")

                    Card {
                        ForEach(Array(monitor.allowedVolumes.enumerated()), id: \.element.id) { index, volume in
                            if index > 0 { RowDivider() }
                            AllowedVolumeRow(volume: volume) {
                                monitor.forgetAllowed(volume)
                            }
                        }
                    }

                    Caption("Spotlight Off leaves these drives alone. Forget to have indexing disabled again.")
                        .padding(.horizontal, 20).padding(.top, 4)
                }

                // ── Processed Drives Section ─────────────────────────────────
                HStack {
                    SectionHeader("Processed Drives")
                    Spacer()
                    if !monitor.history.isEmpty {
                        Button("Clear All") { monitor.clearHistory() }
                            .foregroundColor(.red).buttonStyle(.borderless)
                            .font(.caption).fontWeight(.semibold)
                            .padding(.top, 20).padding(.trailing, 20)
                    }
                }

                if monitor.history.isEmpty {
                    EmptyState(icon: "externaldrive", title: "No drives processed yet",
                               detail: "Connect an external drive and Spotlight Off will disable indexing automatically.")
                } else {
                    Card {
                        ForEach(Array(monitor.history.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 { RowDivider() }
                            HistoryRow(entry: entry,
                                       dateText: Self.dateFormatter.string(from: entry.date)) {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    monitor.removeEntry(entry)
                                }
                            }
                        }
                    }

                    Caption("Hover over an entry to remove it, or use Clear All.")
                        .padding(.horizontal, 20).padding(.top, 4)
                }

                Spacer(minLength: 20)
            }
            .padding(.top, 8)
        }
        .onAppear { monitor.refreshVolumes() }
    }
}

// MARK: - Full Disk Access Banner

/// Shown at the top of the Settings and Drives tabs while access is missing.
struct FullDiskAccessBanner: View {
    @State private var hasFullDiskAccess = FullDiskAccess.isGranted

    var body: some View {
        Group {
            if !hasFullDiskAccess {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Full Disk Access isn't granted").font(.system(size: 12, weight: .semibold))
                        Text("Spotlight Off can't turn off indexing on your drives until it is.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Open Settings") { FullDiskAccess.openSettings() }
                        .controlSize(.small)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.12)))
                .padding(.horizontal, 20).padding(.top, 12)
            }
        }
        .onAppear { hasFullDiskAccess = FullDiskAccess.isGranted }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            hasFullDiskAccess = FullDiskAccess.isGranted
        }
    }
}

// MARK: - Drive Row

struct DriveRow: View {
    let volume: MountedVolume
    let isAllowed: Bool
    let isBusy: Bool
    let monitor: DriveMonitor

    private var isOff: Bool { volume.indexing == .disabled }

    private var status: (text: String, icon: String, color: Color) {
        switch volume.indexing {
        case .disabled:   return ("Indexing off", "externaldrive.badge.xmark", .orange)
        case .enabled:    return (isAllowed ? "Indexing on · allowed by you" : "Indexing on",
                                  "magnifyingglass", .blue)
        case .unexpected: return ("Unexpected indexing state", "questionmark", .gray)
        case .unknown, nil: return ("Indexing state unknown", "questionmark", .gray)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(status.color.opacity(0.12)).frame(width: 28, height: 28)
                Image(systemName: status.icon).foregroundColor(status.color)
                    .font(.system(size: 13))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(volume.name).fontWeight(.medium).font(.system(size: 13))
                Text(status.text).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if isBusy { ProgressView().controlSize(.small) }
            if isOff {
                Button("Re-enable") { monitor.reEnableIndexing(volume) }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(isBusy)
            } else {
                Button("Turn Off") { monitor.disableIndexing(volume) }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(isBusy)
            }
            Menu {
                Button("Open in Finder") { monitor.openInFinder(volume) }
                Divider()
                Button("Remove Spotlight Index…") { DriveActions.removeSpotlightIndex(volume, monitor: monitor) }
                    .disabled(volume.indexing == .enabled)
                Button("Remove macOS Clutter…") { DriveActions.removeClutter(volume, monitor: monitor) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .disabled(isBusy)
            .help("More actions")
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - Allowed Volume Row

struct AllowedVolumeRow: View {
    let volume: AllowedVolume
    let onForget: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.blue.opacity(0.12)).frame(width: 28, height: 28)
                Image(systemName: "magnifyingglass").foregroundColor(.blue)
                    .font(.system(size: 13))
            }
            Text(volume.name).fontWeight(.medium).font(.system(size: 13))
            Spacer()
            Button("Forget", action: onForget)
                .buttonStyle(.bordered).controlSize(.small)
                .help("Disable indexing on this drive again — now if it's connected, otherwise the next time it's plugged in")
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - History Row

struct HistoryRow: View {
    let entry: DriveEntry
    let dateText: String
    let onDelete: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.green.opacity(0.12)).frame(width: 28, height: 28)
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    .font(.system(size: 14))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).fontWeight(.medium).font(.system(size: 13))
                Text(entry.path).font(.caption).foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if hovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove from history")
            } else {
                Text(dateText)
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
}

// MARK: - Building Blocks

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title.uppercased())
            .font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 6)
    }
}

struct SettingsRow<Content: View>: View {
    let icon: String
    let iconColor: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(iconColor)
            }
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

/// The rounded, bordered group used for every list in the settings window.
struct Card<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0, content: content)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
            .padding(.horizontal, 20)
    }
}

struct RowDivider: View {
    var body: some View { Divider().padding(.leading, 44) }
}

struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption2).foregroundColor(.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct EmptyState: View {
    let icon: String?
    let title: String
    let detail: String?

    var body: some View {
        VStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 28)).foregroundColor(.secondary.opacity(0.3))
            } else {
                ProgressView().controlSize(.small)
            }
            Text(title).foregroundColor(.secondary).font(.subheadline)
            if let detail {
                Text(detail)
                    .foregroundColor(.secondary.opacity(0.6)).font(.caption)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28).padding(.horizontal, 20)
    }
}
