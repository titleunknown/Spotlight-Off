import Foundation
import Combine

/// Checks GitHub Releases for a newer version — on demand, and (unless turned
/// off in settings) automatically about once a day.
@MainActor
final class UpdateChecker: ObservableObject {
    enum UpdateState: Equatable {
        case idle, checking, upToDate
        case updateAvailable(String, URL)
        case error(String)
    }

    @Published private(set) var state: UpdateState = .idle

    var isChecking: Bool { inFlight }

    private var inFlight = false
    private var scheduler: Task<Void, Never>?
    private static let checkInterval: TimeInterval = 24 * 60 * 60
    private nonisolated static let releasesURL =
        URL(string: "https://api.github.com/repos/titleunknown/Spotlight-Off/releases/latest")!

    func startAutomaticChecks() {
        scheduler?.cancel()
        scheduler = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))  // stay out of the way at login
            while !Task.isCancelled {
                self?.checkIfDue()
                try? await Task.sleep(for: .seconds(60 * 60))
            }
        }
    }

    private func checkIfDue() {
        guard UserDefaults.standard.bool(forKey: PrefKey.autoCheckUpdates) else { return }
        let last = UserDefaults.standard.object(forKey: PrefKey.lastUpdateCheck) as? Date ?? .distantPast
        if Date().timeIntervalSince(last) >= Self.checkInterval { check(userInitiated: false) }
    }

    /// User-initiated checks show progress and errors in the UI; automatic
    /// checks stay quiet unless they find an update, which is announced once.
    func check(userInitiated: Bool = true) {
        guard !inFlight else { return }
        inFlight = true
        if userInitiated { state = .checking }
        Task {
            let result = await Self.fetchLatestRelease()
            inFlight = false
            UserDefaults.standard.set(Date(), forKey: PrefKey.lastUpdateCheck)
            switch result {
            case .success(let release):
                if Self.isNewer(Self.normalizedVersion(release.tag), than: AppInfo.version) {
                    state = .updateAvailable(release.tag, release.url)
                    if !userInitiated { announce(tag: release.tag, url: release.url) }
                } else {
                    state = .upToDate
                }
            case .failure(let error):
                if userInitiated {
                    state = .error(error.message)
                } else {
                    LogStore.shared.log("Automatic update check failed: \(error.message)", kind: .info)
                }
            }
        }
    }

    private func announce(tag: String, url: URL) {
        LogStore.shared.log("Update available: \(tag)", kind: .info)
        guard UserDefaults.standard.string(forKey: PrefKey.notifiedUpdateVersion) != tag else { return }
        UserDefaults.standard.set(tag, forKey: PrefKey.notifiedUpdateVersion)
        Notifier.shared.post(Notice(title: "Spotlight Off \(tag) is available",
                                    subtitle: "Click to open the download page",
                                    kind: .info, url: url, isDriveEvent: false))
    }

    // MARK: - Networking

    struct Release: Sendable { let tag: String; let url: URL }
    struct UpdateError: Error, Sendable { let message: String }

    private struct ReleaseJSON: Decodable {
        let tagName: String
        let htmlURL: String
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    private nonisolated static func fetchLatestRelease() async -> Result<Release, UpdateError> {
        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return .failure(UpdateError(message: "GitHub returned HTTP \(http.statusCode)."))
            }
            guard let json = try? JSONDecoder().decode(ReleaseJSON.self, from: data),
                  let url = URL(string: json.htmlURL)
            else { return .failure(UpdateError(message: "Could not parse release info.")) }
            return .success(Release(tag: json.tagName, url: url))
        } catch {
            return .failure(UpdateError(message: error.localizedDescription))
        }
    }

    // MARK: - Version Comparison

    nonisolated static func normalizedVersion(_ tag: String) -> String {
        tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
    }

    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let parse: (String) -> [Int] = { v in v.split(separator: ".").compactMap { Int($0) } }
        let av = parse(a), bv = parse(b)
        for i in 0..<max(av.count, bv.count) {
            let ai = i < av.count ? av[i] : 0
            let bi = i < bv.count ? bv[i] : 0
            if ai != bi { return ai > bi }
        }
        return false
    }
}
