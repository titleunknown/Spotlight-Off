import SwiftUI
import ServiceManagement

// MARK: - Data Model

struct DriveEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let path: String
    let date: Date

    init(name: String, path: String) {
        self.id   = UUID()
        self.name = name
        self.path = path
        self.date = Date()
    }
}

// MARK: - Log Store

class LogStore: ObservableObject {
    static let shared = LogStore()
    @Published var entries: [String] = []

    func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(timestamp)] \(message)"
        print(line)
        DispatchQueue.main.async {
            self.entries.append(line)
            if self.entries.count > 200 { self.entries.removeFirst() }
        }
    }
}

// MARK: - App Entry Point

@main
struct SpotlightOffApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    let driveMonitor = DriveMonitor()
    private var settingsWindow: NSWindow?
    private var welcomeWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register defaults — notificationsEnabled is on by default
        UserDefaults.standard.register(defaults: ["notificationsEnabled": true])
        NSApp.setActivationPolicy(.accessory)
        setupMenuBar()
        driveMonitor.start()
        if !UserDefaults.standard.bool(forKey: "hasSeenWelcome") {
            showWelcome()
        }
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "externaldrive.badge.xmark",
                                   accessibilityDescription: "Spotlight Off")
            button.image?.isTemplate = true
        }
        buildMenu()
        driveMonitor.onHistoryChanged = { [weak self] in
            DispatchQueue.main.async { self?.buildMenu() }
        }
    }

    func buildMenu() {
        let menu = NSMenu()
        let header = NSMenuItem(title: "Spotlight Off — Active", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let history = driveMonitor.history
        if history.isEmpty {
            let empty = NSMenuItem(title: "No drives processed yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for entry in history.prefix(5) {
                let item = NSMenuItem(title: "✓  \(entry.name)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                item.toolTip = entry.path
                menu.addItem(item)
            }
            if history.count > 5 {
                let more = NSMenuItem(title: "  + \(history.count - 5) more…", action: nil, keyEquivalent: "")
                more.isEnabled = false
                menu.addItem(more)
            }
        }

        menu.addItem(.separator())
        let setupItem = NSMenuItem(title: "Setup Guide…", action: #selector(showWelcome), keyEquivalent: "")
        setupItem.target = self
        menu.addItem(setupItem)
        let settingsItem = NSMenuItem(title: "History & Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Spotlight Off",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func openSettings() {
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let view = NSHostingView(rootView: SettingsView(monitor: driveMonitor))
        view.frame = NSRect(x: 0, y: 0, width: 440, height: 600)
        let window = NSWindow(contentRect: view.frame,
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "History & Settings — Spotlight Off"
        window.contentView = view
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        settingsWindow = window
    }

    @objc func showWelcome() {
        if let window = welcomeWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let view = NSHostingView(rootView: WelcomeView {
            self.welcomeWindow?.close()
            UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
        })
        view.frame = NSRect(x: 0, y: 0, width: 500, height: 680)
        let window = NSWindow(contentRect: view.frame,
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Welcome to Spotlight Off"
        window.contentView = view
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        welcomeWindow = window
    }
}

// MARK: - Drive Monitor

class DriveMonitor: ObservableObject {
    @Published var history: [DriveEntry] = []
    var onHistoryChanged: (() -> Void)?
    private let historyKey = "spotlightoff.history"

    init() { loadHistory() }

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(volumeMounted(_:)),
            name: NSWorkspace.didMountNotification, object: nil)
    }

    @objc private func volumeMounted(_ notification: NSNotification) {
        guard let path = notification.userInfo?["NSDevicePath"] as? String else { return }
        LogStore.shared.log("Volume mounted: \(path)")

        let url = URL(fileURLWithPath: path)
        guard isExternalVolume(url) else {
            LogStore.shared.log("Skipped (not an external volume): \(path)")
            return
        }

        if isTimeMachineVolume(path) {
            LogStore.shared.log("Skipped (Time Machine volume): \(path)")
            return
        }

        let resolvedPath: String
        if path.hasPrefix("/Volumes/") {
            let candidate = "/System/Volumes/Data" + path
            resolvedPath = FileManager.default.fileExists(atPath: candidate) ? candidate : path
        } else {
            resolvedPath = path
        }
        LogStore.shared.log("Resolved path: \(resolvedPath)")

        let name = url.lastPathComponent.isEmpty ? "External Drive" : url.lastPathComponent
        LogStore.shared.log("Accepted — scheduling disable for: \(name)")

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 4.0) { [weak self] in
            self?.handleVolume(resolvedPath: resolvedPath, volumesPath: path, name: name)
        }
    }

    // MARK: - Time Machine Detection

    /// Returns true if the volume at the given path is a Time Machine backup destination.
    /// Covers APFS (.timemachine hidden mount), HFS+ (Backups.backupdb), and
    /// any volume registered as a TM destination in tmutil.
    private func isTimeMachineVolume(_ volumePath: String) -> Bool {
        // 1. APFS TM volumes mount under /Volumes/.timemachine/
        if volumePath.contains("/.timemachine") {
            return true
        }

        // 2. HFS+ TM volumes have a Backups.backupdb folder at root
        let backupDB = (volumePath as NSString).appendingPathComponent("Backups.backupdb")
        if FileManager.default.fileExists(atPath: backupDB) {
            return true
        }

        // 3. Cross-reference against tmutil's registered TM destinations
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["destinationinfo", "-X"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // suppress stderr
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let destinations = plist["Destinations"] as? [[String: Any]] {
                for dest in destinations {
                    if let mountPoint = dest["MountPoint"] as? String,
                       mountPoint == volumePath {
                        return true
                    }
                }
            }
        } catch {
            // tmutil unavailable or failed — fall through
        }

        return false
    }

    private func isExternalVolume(_ url: URL) -> Bool {
        guard let vals = try? url.resourceValues(forKeys: [
            .volumeIsRootFileSystemKey, .volumeIsInternalKey,
            .volumeIsLocalKey, .volumeIsRemovableKey
        ]) else {
            LogStore.shared.log("Could not read volume flags for \(url.path)")
            return false
        }
        let isRoot     = vals.volumeIsRootFileSystem ?? false
        let isInternal = vals.volumeIsInternal       ?? false
        let isLocal    = vals.volumeIsLocal           ?? false
        let isRemovable = vals.volumeIsRemovable      ?? false
        LogStore.shared.log("Flags — root:\(isRoot) internal:\(isInternal) local:\(isLocal) removable:\(isRemovable)")
        if isRoot || isInternal || !isLocal { return false }
        return true
    }

    private func handleVolume(resolvedPath: String, volumesPath: String, name: String) {
        guard let status = mdutilStatus(path: resolvedPath) else {
            LogStore.shared.log("Could not read mdutil status for '\(name)' — skipping")
            return
        }
        if status.contains("disabled") {
            LogStore.shared.log("Indexing already disabled for '\(name)'")
            ToastManager.shared.show(.alreadyOff(name))
            return
        }
        if status.contains("unexpected") {
            LogStore.shared.log("Unexpected indexing state for '\(name)' — skipping")
            return
        }
        LogStore.shared.log("Indexing enabled for '\(name)' — disabling")
        let ok = runMdutilAsAdmin(path: volumesPath)
        LogStore.shared.log("Disable succeeded: \(ok)")
        if ok {
            DispatchQueue.main.async { [weak self] in
                self?.addToHistory(name: name, path: volumesPath)
            }
            ToastManager.shared.show(.disabled(name))
        } else {
            ToastManager.shared.show(.failed(name))
        }
    }

    private func mdutilStatus(path: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/mdutil")
        p.arguments = ["-s", path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = pipe
        do {
            try p.run(); p.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            LogStore.shared.log("mdutil -s [\(path)]: \(trimmed)")
            if trimmed.contains("could not") || trimmed.contains("no such") { return nil }
            return trimmed
        } catch {
            LogStore.shared.log("mdutil -s error: \(error)")
            return nil
        }
    }

    private func runMdutilAsAdmin(path: String) -> Bool {
        // Full Disk Access is sufficient for mdutil -i off — no root needed.
        // We call mdutil directly via Process() using the /Volumes path.
        // The OS resolves it to /System/Volumes/Data/Volumes/X internally.
        LogStore.shared.log("Running mdutil for: \(path)")

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/mdutil")
        p.arguments = ["-i", "off", path]
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError  = errPipe
        do {
            try p.run()
            p.waitUntilExit()
            let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let combined = (out + err).trimmingCharacters(in: .whitespacesAndNewlines)
            LogStore.shared.log("mdutil out: \(combined)")
            LogStore.shared.log("mdutil exit: \(p.terminationStatus)")
            let lower = combined.lowercased()
            return p.terminationStatus == 0
                && !lower.contains("error")
                && !lower.contains("could not")
        } catch {
            LogStore.shared.log("mdutil threw: \(error)")
            return false
        }
    }

    private func addToHistory(name: String, path: String) {
        history.removeAll { $0.path == path }
        history.insert(DriveEntry(name: name, path: path), at: 0)
        if history.count > 100 { history = Array(history.prefix(100)) }
        saveHistory()
        onHistoryChanged?()
    }

    func removeEntries(at offsets: IndexSet) {
        history.remove(atOffsets: offsets); saveHistory(); onHistoryChanged?()
    }

    func clearHistory() {
        history.removeAll(); saveHistory(); onHistoryChanged?()
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    private func loadHistory() {
        guard let data    = UserDefaults.standard.data(forKey: historyKey),
              let decoded = try? JSONDecoder().decode([DriveEntry].self, from: data)
        else { return }
        history = decoded
    }
}

// MARK: - Toast Manager

enum ToastKind {
    case disabled(String)      // indexing successfully disabled
    case alreadyOff(String)    // was already disabled
    case failed(String)        // mdutil failed
}

class ToastManager {
    static let shared = ToastManager()
    private var panel: NSPanel?
    private var hideTimer: Timer?

    func show(_ kind: ToastKind) {
        guard UserDefaults.standard.bool(forKey: "notificationsEnabled") else { return }

        DispatchQueue.main.async { [weak self] in
            self?.present(kind)
        }
    }

    private func present(_ kind: ToastKind) {
        // Dismiss any existing toast immediately
        hideTimer?.invalidate()
        panel?.close()

        let (icon, title, subtitle, iconColor): (String, String, String, NSColor) = {
            switch kind {
            case .disabled(let name):
                return ("checkmark.circle.fill", name, "Spotlight indexing disabled", .systemGreen)
            case .alreadyOff(let name):
                return ("checkmark.circle", name, "Spotlight already off", .systemBlue)
            case .failed(let name):
                return ("xmark.circle.fill", name, "Could not disable indexing", .systemRed)
            }
        }()

        let hostingView = NSHostingView(rootView: ToastView(
            icon: icon, title: title, subtitle: subtitle,
            iconColor: Color(iconColor)
        ))
        hostingView.frame = NSRect(x: 0, y: 0, width: 280, height: 64)

        // NSPanel with .nonactivatingPanel so it never steals focus
        let p = NSPanel(
            contentRect: hostingView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.contentView = hostingView
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .stationary]
        p.isMovable = false
        p.ignoresMouseEvents = true

        // Position: top-right of the main screen, below menu bar
        if let screen = NSScreen.main {
            let sw = screen.visibleFrame.width
            let sx = screen.visibleFrame.origin.x
            let sy = screen.visibleFrame.origin.y + screen.visibleFrame.height
            let margin: CGFloat = 16
            let x = sx + sw - hostingView.frame.width - margin
            let y = sy - hostingView.frame.height - margin
            p.setFrameOrigin(NSPoint(x: x, y: y))
        }

        p.alphaValue = 0
        p.orderFrontRegardless()
        panel = p

        // Fade in
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            p.animator().alphaValue = 1
        }

        // Auto-dismiss after 3.5 seconds
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func dismiss() {
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            p.animator().alphaValue = 0
        }, completionHandler: {
            p.close()
            self.panel = nil
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
        .padding(6) // room for shadow
    }
}



class UpdateChecker: ObservableObject {
    enum UpdateState {
        case idle, checking, upToDate, updateAvailable(String, URL), error(String)
    }

    @Published var state: UpdateState = .idle

    var isChecking: Bool {
        if case .checking = state { return true }
        return false
    }

    private let currentVersion: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }()

    func check() {
        state = .checking
        let url = URL(string: "https://api.github.com/repos/titleunknown/Spotlight-Off/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.state = .error(error.localizedDescription)
                    return
                }
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String,
                      let htmlURL = json["html_url"] as? String,
                      let releaseURL = URL(string: htmlURL)
                else {
                    self.state = .error("Could not parse release info.")
                    return
                }

                // Strip leading 'v' for comparison
                let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                if self.isNewer(latest, than: self.currentVersion) {
                    self.state = .updateAvailable(tag, releaseURL)
                } else {
                    self.state = .upToDate
                }
            }
        }.resume()
    }

    /// Returns true if `a` is a higher semantic version than `b`.
    private func isNewer(_ a: String, than b: String) -> Bool {
        let parse: (String) -> [Int] = { v in
            v.split(separator: ".").compactMap { Int($0) }
        }
        let av = parse(a), bv = parse(b)
        for i in 0..<max(av.count, bv.count) {
            let ai = i < av.count ? av[i] : 0
            let bi = i < bv.count ? bv[i] : 0
            if ai != bi { return ai > bi }
        }
        return false
    }
}



struct SettingsView: View {
    @ObservedObject var monitor: DriveMonitor
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @StateObject private var updater = UpdateChecker()
    @State private var notificationsEnabled: Bool = (UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool) ?? true

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium; f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

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
            }
            .padding(.horizontal, 16).padding(.vertical, 14)

            Divider()

            // ── Settings ────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 12) {
                Label("SETTINGS", systemImage: "")
                    .font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
                    .labelStyle(.titleOnly)

                HStack {
                    Image(systemName: "arrow.up.circle")
                        .foregroundColor(.secondary).frame(width: 16)
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            do {
                                if enabled { try SMAppService.mainApp.register() }
                                else       { try SMAppService.mainApp.unregister() }
                                launchAtLogin = SMAppService.mainApp.status == .enabled
                            } catch {
                                LogStore.shared.log("Launch at login error: \(error)")
                                launchAtLogin = SMAppService.mainApp.status == .enabled
                            }
                        }
                }

                HStack {
                    Image(systemName: "bell")
                        .foregroundColor(.secondary).frame(width: 16)
                    Toggle("Show drive notifications", isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { _, enabled in
                            UserDefaults.standard.set(enabled, forKey: "notificationsEnabled")
                        }
                }

                Divider()

                HStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(.secondary).frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        switch updater.state {
                        case .idle:
                            Text("Check for Updates")
                                .font(.caption).foregroundColor(.primary)
                        case .checking:
                            Text("Checking…")
                                .font(.caption).foregroundColor(.secondary)
                        case .upToDate:
                            Text("You're up to date ✓")
                                .font(.caption).foregroundColor(.green)
                        case .updateAvailable(let tag, _):
                            Text("Update available: \(tag)")
                                .font(.caption).foregroundColor(.orange)
                        case .error(let msg):
                            Text("Error: \(msg)")
                                .font(.caption).foregroundColor(.red)
                        }
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
            .padding(.horizontal, 16).padding(.vertical, 14)

            Divider()

            // ── Processed Drives ────────────────────────────────────────────
            HStack {
                Label("PROCESSED DRIVES", systemImage: "")
                    .font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
                    .labelStyle(.titleOnly)
                Spacer()
                if !monitor.history.isEmpty {
                    Button("Clear All") { monitor.clearHistory() }
                        .foregroundColor(.red).buttonStyle(.borderless)
                        .font(.caption).fontWeight(.semibold)
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)

            if monitor.history.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 28)).foregroundColor(.secondary.opacity(0.3))
                    Text("No drives processed yet")
                        .foregroundColor(.secondary).font(.subheadline)
                    Text("Connect an external drive and Spotlight Off\nwill disable indexing automatically.")
                        .foregroundColor(.secondary.opacity(0.6)).font(.caption)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 28)
            } else {
                List {
                    ForEach(monitor.history) { entry in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name).fontWeight(.medium)
                                Text(entry.path).font(.caption).foregroundColor(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Text(dateFormatter.string(from: entry.date))
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                    .onDelete { offsets in monitor.removeEntries(at: offsets) }
                }
                .frame(height: 200)
                Text("Select an entry and press Delete to remove it, or use Clear All.")
                    .font(.caption2).foregroundColor(.secondary.opacity(0.5))
                    .padding(.horizontal, 16).padding(.bottom, 6)
            }

            Divider()

            // ── Activity Log ────────────────────────────────────────────────
            HStack {
                Label("ACTIVITY LOG", systemImage: "")
                    .font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
                    .labelStyle(.titleOnly)
                Spacer()
                CopyLogButton()
                Button("Clear") { LogStore.shared.entries.removeAll() }
                    .buttonStyle(.borderless).font(.caption).fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)

            LogView().frame(height: 110)

            Divider()

            // ── Footer ──────────────────────────────────────────────────────
            HStack(spacing: 4) {
                Text("By")
                    .font(.caption2).foregroundColor(.secondary.opacity(0.5))
                Button("FAINI MADE") {
                    NSWorkspace.shared.open(URL(string: "https://www.fainimade.com")!)
                }
                .buttonStyle(.plain)
                .font(.caption2).fontWeight(.semibold)
                .foregroundColor(.secondary.opacity(0.7))

                Text("·")
                    .font(.caption2).foregroundColor(.secondary.opacity(0.3))

                Button("GitHub") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/titleunknown/Spotlight-Off")!)
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.5))

                Text("·")
                    .font(.caption2).foregroundColor(.secondary.opacity(0.3))

                Button("CC BY-NC 4.0") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/titleunknown/Spotlight-Off/blob/main/LICENSE")!)
                }
                .buttonStyle(.plain)
                .font(.caption2).foregroundColor(.secondary.opacity(0.5))

                Spacer()

                Text("Full Disk Access required")
                    .font(.caption2).foregroundColor(.secondary.opacity(0.4))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .frame(width: 460)
    }
}

// MARK: - Copy Log Button

struct CopyLogButton: View {
    @State private var copied = false

    var body: some View {
        Button(action: {
            let text = LogStore.shared.entries.joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            withAnimation(.easeInOut(duration: 0.15)) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation(.easeInOut(duration: 0.15)) { copied = false }
            }
        }) {
            Label(copied ? "Copied!" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(copied ? .green : .secondary)
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - Log View

struct LogView: View {
    @ObservedObject var store = LogStore.shared

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(store.entries.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .padding(8)
            }
            .background(Color(NSColor.textBackgroundColor).opacity(0.4))
            .onChange(of: store.entries.count) { _, _ in
                if let last = store.entries.indices.last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - FDA Checker

class FDAChecker: ObservableObject {
    @Published var hasAccess: Bool = false
    private var timer: Timer?

    init() {
        check()
        // Poll every 2 seconds so the badge updates live when the user grants access
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    deinit { timer?.invalidate() }

    private func check() {
        // Attempting to list /Library/Application Support/com.apple.TCC
        // (a protected directory) succeeds only if Full Disk Access is granted.
        let probe = "/Library/Application Support/com.apple.TCC"
        let granted = (try? FileManager.default.contentsOfDirectory(atPath: probe)) != nil
        DispatchQueue.main.async { self.hasAccess = granted }
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    var onDismiss: () -> Void
    @StateObject private var fda = FDAChecker()

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.10, blue: 0.16).ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color(red: 0.12, green: 0.16, blue: 0.24))
                            .frame(width: 80, height: 80)
                        ZStack {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 30, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.85))
                            Image(systemName: "line.diagonal")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(Color(red: 0.94, green: 0.33, blue: 0.31))
                        }
                    }
                    .padding(.top, 30)
                    Text("Spotlight Off")
                        .font(.system(size: 26, weight: .bold, design: .rounded)).foregroundColor(.white)
                    Text("A few quick steps to get up and running")
                        .font(.system(size: 12)).foregroundColor(Color.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity).padding(.bottom, 20)

                Divider().background(Color.white.opacity(0.08))

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        SetupStep(
                            number: 1, title: "Grant Full Disk Access",
                            description: "Spotlight Off needs Full Disk Access to disable Spotlight on your drives. Open the link below, then make sure Spotlight Off appears in the list and is toggled on.",
                            action: "Open Full Disk Access →",
                            actionURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
                            verification: fda.hasAccess ? .granted : .missing
                        )
                        SetupStep(
                            number: 2, title: "Enable Launch at Login",
                            description: "Open History & Settings from the menu bar and toggle Launch at Login so Spotlight Off is always running in the background.",
                            action: nil, actionURL: nil, verification: nil
                        )
                        SetupStep(
                            number: 3, title: "That's it!",
                            description: "When you connect an external drive, Spotlight Off will automatically disable indexing — no password prompt required. Full Disk Access gives the app everything it needs.",
                            action: nil, actionURL: nil, verification: nil
                        )
                    }
                    .padding(.horizontal, 24).padding(.vertical, 8)
                }

                Divider().background(Color.white.opacity(0.08))

                VStack(spacing: 12) {
                    Text("Free, open source, and CC BY-NC 4.0 licensed. Made by Faini Made. If it saves you time, consider supporting development.")
                        .font(.system(size: 11)).foregroundColor(Color.white.opacity(0.4))
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        DonateButton(label: "PayPal", icon: "💳",
                            url: "https://www.paypal.com/donate/?hosted_button_id=AEY7AC82BKH5C",
                            color: Color(red: 0.0, green: 0.47, blue: 0.75))
                        DonateButton(label: "Venmo", icon: "✦",
                            url: "https://account.venmo.com/u/FAINI",
                            color: Color(red: 0.22, green: 0.72, blue: 0.60))
                        DonateButton(label: "Coffee", icon: "☕",
                            url: "https://buymeacoffee.com/fainimade",
                            color: Color(red: 1.0, green: 0.75, blue: 0.15))
                    }
                    Button(action: onDismiss) {
                        Text("Get Started").font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white).frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(red: 0.94, green: 0.33, blue: 0.31))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(22)
            }
        }
        .frame(width: 500, height: 680)
    }
}

// MARK: - Setup Step

enum VerificationStatus { case granted, missing }

struct SetupStep: View {
    let number: Int
    let title: String
    let description: String
    let action: String?
    let actionURL: String?
    var verification: VerificationStatus?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Number badge — turns into a checkmark when verification passes
            ZStack {
                Circle()
                    .fill(badgeColor.opacity(0.85))
                    .frame(width: 26, height: 26)
                if verification == .granted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .padding(.top, 2)
            .animation(.easeInOut(duration: 0.3), value: verification == .granted)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)

                    // Inline status badge
                    if let v = verification {
                        HStack(spacing: 4) {
                            Image(systemName: v == .granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .font(.system(size: 10))
                            Text(v == .granted ? "Granted" : "Not granted")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(v == .granted ? .green : Color(red: 1.0, green: 0.75, blue: 0.15))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(
                            Capsule().fill(v == .granted
                                ? Color.green.opacity(0.15)
                                : Color(red: 1.0, green: 0.75, blue: 0.15).opacity(0.15))
                        )
                        .animation(.easeInOut(duration: 0.3), value: v == .granted)
                    }
                }

                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)

                if let action = action, let urlString = actionURL, let url = URL(string: urlString) {
                    Button(action) { NSWorkspace.shared.open(url) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 0.94, green: 0.33, blue: 0.31))
                        .padding(.top, 2)
                }
            }
            Spacer()
        }
        .padding(.vertical, 14)
        .overlay(Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1), alignment: .bottom)
    }

    private var badgeColor: Color {
        if verification == .granted { return .green }
        return Color(red: 0.94, green: 0.33, blue: 0.31)
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
            .frame(maxWidth: .infinity).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(hovered ? color.opacity(0.3) : color.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(color.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain).onHover { hovered = $0 }
    }
}
