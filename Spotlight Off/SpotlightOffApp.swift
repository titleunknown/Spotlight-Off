import SwiftUI
import UserNotifications

// MARK: - App Entry Point
// Using an empty WindowGroup (never shown) instead of Settings {} to avoid
// the blank "Spotlight Off Settings" window that macOS Tahoe auto-opens.

@main
struct SpotlightOffApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // We manage all windows manually via AppDelegate.
        // The WindowGroup is required by the App protocol but is never shown.
        WindowGroup {
            Color.clear.frame(width: 0, height: 0)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 0, height: 0)
        .commandsRemoved()
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    let driveMonitor = DriveMonitor()
    let updater = UpdateChecker()
    let navigation = SettingsNavigation()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests run hosted inside the app: don't watch (and change) real drives.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }

        PrefKey.registerDefaults()
        NSApp.setActivationPolicy(.accessory)

        // Close any windows the SwiftUI App scene may have opened before we
        // had a chance to set the accessory policy (fixes blank window on Tahoe).
        for window in NSApp.windows { window.close() }

        UNUserNotificationCenter.current().delegate = self
        Notifier.shared.requestAuthorizationIfNeeded()
        setupMenuBar()
        driveMonitor.start()
        updater.startAutomaticChecks()

        if !FullDiskAccess.isGranted {
            LogStore.shared.log("Full Disk Access isn't granted — drives can't be processed until it is (History & Settings → Setup)", kind: .failure)
        }
        // First launch: open straight to the setup checklist.
        if !UserDefaults.standard.bool(forKey: PrefKey.hasSeenWelcome) {
            UserDefaults.standard.set(true, forKey: PrefKey.hasSeenWelcome)
            openSetup()
        }
    }

    // Relaunching the app from Finder/Launchpad while it's running would
    // otherwise make SwiftUI open a blank WindowGroup window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "externaldrive.badge.xmark",
                                   accessibilityDescription: "Spotlight Off")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
    }

    /// Rebuilt every time the menu opens, so it always reflects current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }
        menu.removeAllItems()

        menu.addItem(disabledItem("Spotlight Off — Active"))
        if !FullDiskAccess.isGranted {
            menu.addItem(actionItem("Full Disk Access Needed…", #selector(openSetup),
                                    symbol: "exclamationmark.triangle.fill"))
        }
        if case .updateAvailable(let tag, let url) = updater.state {
            let item = actionItem("Update Available: \(tag)…", #selector(openURL(_:)),
                                  symbol: "arrow.down.circle.fill")
            item.representedObject = url
            menu.addItem(item)
        }

        // Connected drives, each with its own submenu of actions.
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Connected Drives"))
        let drives = driveMonitor.connectedDrives
        if drives.isEmpty {
            menu.addItem(disabledItem("No external drives connected"))
        }
        for drive in drives {
            let item = NSMenuItem(title: drive.name, action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: drive.indexing == .disabled ? "externaldrive.badge.xmark" : "externaldrive",
                                 accessibilityDescription: nil)
            item.submenu = driveSubmenu(for: drive)
            menu.addItem(item)
        }

        // Recently processed drives; connected ones open in Finder.
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Recently Processed"))
        let history = driveMonitor.history
        if history.isEmpty {
            menu.addItem(disabledItem("No drives processed yet"))
        }
        let connectedPaths = Set(drives.map(\.path))
        for entry in history.prefix(5) {
            let isConnected = connectedPaths.contains(entry.path)
            let item = actionItem("✓  \(entry.name)", #selector(openPath(_:)))
            item.representedObject = entry.path
            item.isEnabled = isConnected
            item.toolTip = isConnected ? "Open in Finder" : "\(entry.path) — not connected"
            menu.addItem(item)
        }
        if history.count > 5 {
            menu.addItem(disabledItem("  + \(history.count - 5) more…"))
        }

        menu.addItem(.separator())
        let settings = actionItem("History & Settings…", #selector(openSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Spotlight Off",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func driveSubmenu(for drive: MountedVolume) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let allowed = drive.uuid.map(driveMonitor.isAllowed) ?? false
        let status: String = {
            switch drive.indexing {
            case .disabled:     return "Spotlight indexing: Off"
            case .enabled:      return allowed ? "Spotlight indexing: On (allowed by you)" : "Spotlight indexing: On"
            case .unexpected:   return "Spotlight indexing: Unexpected state"
            case .unknown, nil: return "Spotlight indexing: Unknown"
            }
        }()
        menu.addItem(disabledItem(status))
        menu.addItem(.separator())

        let busy = driveMonitor.busyPaths.contains(drive.path)
        func add(_ title: String, _ action: Selector, enabled: Bool = true) {
            let item = actionItem(title, action)
            item.representedObject = drive.path
            item.isEnabled = enabled && !busy
            menu.addItem(item)
        }
        add("Open in Finder", #selector(openPath(_:)))
        if drive.indexing == .disabled {
            add("Turn Spotlight Back On", #selector(reEnableDrive(_:)))
        } else {
            add("Turn Spotlight Off", #selector(disableDrive(_:)))
        }
        menu.addItem(.separator())
        add("Remove Spotlight Index…", #selector(removeIndex(_:)), enabled: drive.indexing != .enabled)
        add("Remove macOS Clutter…", #selector(removeClutter(_:)))
        return menu
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, _ action: Selector, symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    // MARK: - Menu Actions

    private func drive(for sender: NSMenuItem) -> MountedVolume? {
        guard let path = sender.representedObject as? String else { return nil }
        return driveMonitor.connectedDrives.first { $0.path == path }
    }

    @objc private func openPath(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc private func openURL(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.open(url) }
    }

    @objc private func reEnableDrive(_ sender: NSMenuItem) {
        if let drive = drive(for: sender) { driveMonitor.reEnableIndexing(drive) }
    }

    @objc private func disableDrive(_ sender: NSMenuItem) {
        if let drive = drive(for: sender) { driveMonitor.disableIndexing(drive) }
    }

    @objc private func removeIndex(_ sender: NSMenuItem) {
        if let drive = drive(for: sender) { DriveActions.removeSpotlightIndex(drive, monitor: driveMonitor) }
    }

    @objc private func removeClutter(_ sender: NSMenuItem) {
        if let drive = drive(for: sender) { DriveActions.removeClutter(drive, monitor: driveMonitor) }
    }

    // MARK: - Windows

    @objc func openSettings() {
        if settingsWindow == nil {
            let view = NSHostingView(rootView: SettingsView(monitor: driveMonitor, updater: updater,
                                                            navigation: navigation))
            view.frame = NSRect(x: 0, y: 0, width: 500, height: 640)
            let window = NSWindow(contentRect: view.frame,
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "Spotlight Off"
            window.contentView = view
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        driveMonitor.refreshVolumes()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    @objc func openSetup() {
        navigation.tab = .setup
        openSettings()
    }

    // MARK: - Notifications

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    /// Clicking a notification opens its link (update notices) or the settings window.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let link = response.notification.request.content.userInfo["url"] as? String
        await MainActor.run {
            if let link, let url = URL(string: link) {
                NSWorkspace.shared.open(url)
            } else {
                openSettings()
            }
        }
    }
}
