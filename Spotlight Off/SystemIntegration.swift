import AppKit
import ServiceManagement

// MARK: - Full Disk Access

enum FullDiskAccess {
    static let settingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    /// There's no public API for checking Full Disk Access, so apps have long
    /// probed a location that's unreadable without it. macOS 27 moved the TCC
    /// database into a protected container, breaking the classic probe of
    /// "/Library/Application Support/com.apple.TCC". ~/Library/Safari exists
    /// on every Mac regardless of Safari usage and has required Full Disk
    /// Access to read since it was introduced, so it works across every
    /// supported OS version — the old TCC path stays as a fallback in case a
    /// future OS removes Safari's folder too.
    static var isGranted: Bool {
        #if DEBUG
        if ScreenshotMode.isActive { return true }
        #endif
        let candidates = [
            "\(NSHomeDirectory())/Library/Safari",
            "/Library/Application Support/com.apple.TCC"
        ]
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return false
        }
        return (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
    }

    static func openSettings() { NSWorkspace.shared.open(settingsURL) }
}

// MARK: - Finder .DS_Store Setting

/// Finder's own "don't write .DS_Store files on USB drives" preference
/// (`defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true`).
/// Finder reads it at launch, so changes apply after Finder relaunches.
enum FinderPrefs {
    private static var domain: CFString { "com.apple.desktopservices" as CFString }
    private static var usbKey: CFString { "DSDontWriteUSBStores" as CFString }

    static var preventsDSStoreOnExternalDrives: Bool {
        get {
            #if DEBUG
            if ScreenshotMode.isActive { return true }
            #endif
            return (CFPreferencesCopyAppValue(usbKey, domain) as? Bool) ?? false
        }
        set {
            CFPreferencesSetAppValue(usbKey, newValue ? kCFBooleanTrue : nil, domain)
            CFPreferencesAppSynchronize(domain)
        }
    }

    static func relaunchFinder() {
        // Finder is relaunched automatically by the system after it quits.
        Task.detached {
            _ = try? ProcessRunner.run("/usr/bin/killall", ["Finder"], timeout: 10)
        }
    }
}

// MARK: - Launch at Login

enum LaunchAtLogin {
    static let settingsURL =
        URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!

    static var isEnabled: Bool {
        #if DEBUG
        if ScreenshotMode.isActive { return true }
        #endif
        return SMAppService.mainApp.status == .enabled
    }

    static var needsApproval: Bool {
        #if DEBUG
        if ScreenshotMode.isActive { return false }
        #endif
        return SMAppService.mainApp.status == .requiresApproval
    }

    /// Registers or unregisters the login item and returns the resulting state.
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else       { try SMAppService.mainApp.unregister() }
        } catch {
            LogStore.shared.log("Launch at login error: \(error.localizedDescription)", kind: .failure)
        }
        if enabled && needsApproval {
            LogStore.shared.log("Launch at login needs approval in System Settings → General → Login Items", kind: .failure)
        }
        return isEnabled
    }
}
