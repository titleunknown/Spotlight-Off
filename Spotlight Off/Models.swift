import Foundation

// MARK: - App Info

enum AppInfo {
    /// The marketing version (MARKETING_VERSION in the project), e.g. "1.2.0".
    static let version =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
}

#if DEBUG
// MARK: - Screenshot Mode

/// Set by the screenshot generator in the test target so the settings window
/// shows a fully set-up app (access granted, sample drives) instead of the
/// test machine's real state. Debug builds only.
enum ScreenshotMode {
    nonisolated(unsafe) static var isActive = false
}
#endif

// MARK: - Preference Keys

enum PrefKey {
    static let notificationsEnabled   = "notificationsEnabled"
    static let notificationStyle      = "notificationStyle"
    static let hasSeenWelcome         = "hasSeenWelcome"
    static let removeIndexOnDisable   = "removeIndexOnDisable"
    static let autoCheckUpdates       = "autoCheckUpdates"
    static let lastUpdateCheck        = "lastUpdateCheck"
    static let notifiedUpdateVersion  = "notifiedUpdateVersion"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            notificationsEnabled: true,
            notificationStyle: NotificationStyle.system.rawValue,
            removeIndexOnDisable: false,
            autoCheckUpdates: true,
        ])
    }
}

enum NotificationStyle: String, CaseIterable, Identifiable, Sendable {
    case system, popup
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .popup:  return "Pop-up"
        }
    }
}

// MARK: - Data Model

struct DriveEntry: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let path: String
    let date: Date

    init(name: String, path: String, date: Date = Date()) {
        self.id   = UUID()
        self.name = name
        self.path = path
        self.date = date
    }
}

/// A drive the user re-enabled indexing on. Keyed by volume UUID so it's
/// recognised on every future mount regardless of its mount path.
struct AllowedVolume: Codable, Identifiable, Equatable, Sendable {
    var id: String { uuid }
    let uuid: String
    let name: String
}

/// Spotlight indexing state as reported by `mdutil -s`.
enum IndexingState: Equatable, Sendable {
    case enabled
    case disabled
    /// mdutil reported a state it calls "unexpected" — not safe to act on.
    case unexpected
    /// mdutil answered but without a usable state (e.g. "unknown indexing state").
    case unknown
}

/// A currently-mounted external volume that Spotlight Off manages.
/// Identified by path so repeated scans don't churn the SwiftUI list.
struct MountedVolume: Identifiable, Equatable, Sendable {
    var id: String { path }
    let name: String
    let path: String
    let uuid: String?
    /// nil when `mdutil -s` couldn't be read.
    let indexing: IndexingState?
}
