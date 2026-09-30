import AppKit
import Combine

/// Watches for mounted drives, turns their Spotlight indexing off, and runs
/// the user's drive actions. Blocking work (subprocesses, file walks) runs on
/// background queues via `runInBackground`; all state lives on the main actor.
@MainActor
final class DriveMonitor: ObservableObject {
    @Published private(set) var history: [DriveEntry] = []
    @Published private(set) var connectedDrives: [MountedVolume] = []
    @Published private(set) var isScanningVolumes = false
    /// Drives with an action in flight, so their buttons can be disabled.
    @Published private(set) var busyPaths: Set<String> = []
    @Published private(set) var allowedVolumes: [AllowedVolume] = []

    private let historyKey = "spotlightoff.history"
    /// Drives the user re-enabled indexing on; left alone on future mounts.
    private let allowedKey = "spotlightoff.allowedVolumes"
    /// Bumped per scan so an older scan can't overwrite a newer one.
    private var scanGeneration = 0
    private var observers: [NSObjectProtocol] = []

    init() {
        history = Self.load([DriveEntry].self, key: historyKey) ?? []
        allowedVolumes = Self.load([AllowedVolume].self, key: allowedKey) ?? []
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didMountNotification,
                                            object: nil, queue: .main) { [weak self] note in
            guard let path = note.userInfo?["NSDevicePath"] as? String else { return }
            MainActor.assumeIsolated { self?.process(path: path, atLaunch: false) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didUnmountNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshVolumes() }
        })

        // Drives attached before launch (e.g. at boot with Launch at Login)
        // never produce a mount notification, so sweep them once now.
        Task {
            let paths = await runInBackground { VolumeInspector.mountedVolumePaths() }
            for path in paths { process(path: path, atLaunch: true) }
        }
        refreshVolumes()
    }

    // MARK: - Mount Handling

    private func process(path: String, atLaunch: Bool) {
        if !atLaunch { log("Mounted: \(path)") }
        Task {
            let classification = await runInBackground { VolumeInspector.classify(path: path) }
            switch classification {
            case .notExternal:
                if !atLaunch { log("Skipped — internal or virtual volume: \(path)") }
            case .diskImage:
                if !atLaunch { log("Ignored — disk image: \(path)") }
            case .timeMachine:
                log("Skipped — Time Machine volume: \(path)")
            case .eligible(let name, let uuid):
                refreshVolumes()
                if let uuid, isAllowed(uuid) {
                    log("Skipped — you re-enabled indexing on \"\(name)\"")
                    return
                }
                log(atLaunch ? "Found \"\(name)\" already connected — checking indexing…"
                             : "Accepted \"\(name)\" — disabling indexing in 4s…")
                if !atLaunch { try? await Task.sleep(for: .seconds(4)) }
                await disable(path: path, name: name, announceAlreadyOff: !atLaunch)
            }
        }
    }

    /// Turns indexing off (if needed), records the result and notifies.
    private func disable(path: String, name: String, announceAlreadyOff: Bool) async {
        guard busyPaths.insert(path).inserted else { return }
        let outcome = await runInBackground { VolumeInspector.disableIfNeeded(path: path) }
        busyPaths.remove(path)

        switch outcome {
        case .gone:
            log("\"\(name)\" — volume no longer mounted, skipped")
        case .unreadable:
            log("\"\(name)\" — could not read mdutil status, skipped", kind: .failure)
        case .unexpected:
            log("\"\(name)\" — unexpected mdutil state, skipped", kind: .failure)
        case .alreadyOff:
            log("\"\(name)\" — indexing already off", kind: .success)
            if announceAlreadyOff { notify(name, "Spotlight already off", .info) }
        case .disabled:
            log("\"\(name)\" — Spotlight disabled ✓", kind: .success)
            addToHistory(name: name, path: path)
            notify(name, "Spotlight indexing disabled", .success)
        case .failed(let detail):
            if FullDiskAccess.isGranted {
                log("\"\(name)\" — failed to disable: \(detail)", kind: .failure)
                notify(name, "Could not disable indexing", .failure)
            } else {
                log("\"\(name)\" — failed to disable: \(detail). Full Disk Access isn't granted (History & Settings → Setup)", kind: .failure)
                notify(name, "Needs Full Disk Access — see Setup", .failure)
            }
        }

        if (outcome == .disabled || outcome == .alreadyOff),
           UserDefaults.standard.bool(forKey: PrefKey.removeIndexOnDisable) {
            await removeIndex(path: path, name: name, announce: false)
        }
        refreshVolumes()
    }

    // MARK: - Connected Drives

    func refreshVolumes() {
        #if DEBUG
        if ScreenshotMode.isActive { return }  // keep the sample drives
        #endif
        scanGeneration += 1
        let generation = scanGeneration
        isScanningVolumes = true
        Task {
            let drives = await runInBackground(.userInitiated) { VolumeInspector.scanConnectedDrives() }
            guard generation == scanGeneration else { return }
            connectedDrives = drives
            isScanningVolumes = false
        }
    }

    func isAllowed(_ uuid: String) -> Bool { allowedVolumes.contains { $0.uuid == uuid } }

    func openInFinder(_ volume: MountedVolume) {
        NSWorkspace.shared.open(URL(fileURLWithPath: volume.path))
    }

    /// Turns Spotlight indexing back on for a drive and remembers it, so future
    /// mounts leave its indexing alone. Also drops its "processed" history entry.
    func reEnableIndexing(_ volume: MountedVolume) {
        guard busyPaths.insert(volume.path).inserted else { return }
        log("\"\(volume.name)\" — re-enabling Spotlight…")
        Task {
            let path = volume.path
            let result = await runInBackground(.userInitiated) { () -> MdutilResult? in
                guard FileManager.default.fileExists(atPath: path) else { return nil }
                return VolumeInspector.setIndexing(path: path, enabled: true)
            }
            busyPaths.remove(path)
            defer { refreshVolumes() }

            guard let result else {
                log("\"\(volume.name)\" — volume no longer mounted, skipped")
                return
            }
            guard result.succeeded else {
                log("\"\(volume.name)\" — failed to re-enable: \(result.detail)", kind: .failure)
                notify(volume.name, "Could not re-enable indexing", .failure)
                return
            }
            if let uuid = volume.uuid {
                if !isAllowed(uuid) {
                    saveAllowed(allowedVolumes + [AllowedVolume(uuid: uuid, name: volume.name)])
                }
                log("\"\(volume.name)\" — Spotlight re-enabled ✓ (will be left on in future)", kind: .success)
            } else {
                log("\"\(volume.name)\" — Spotlight re-enabled ✓, but the drive has no UUID so it can't be remembered", kind: .success)
            }
            history.removeAll { $0.path == path }
            saveHistory()
        }
    }

    /// Turns indexing off for a connected drive right away, and stops allowing it.
    func disableIndexing(_ volume: MountedVolume) {
        if let uuid = volume.uuid, isAllowed(uuid) {
            saveAllowed(allowedVolumes.filter { $0.uuid != uuid })
        }
        Task { await disable(path: volume.path, name: volume.name, announceAlreadyOff: true) }
    }

    /// Stops allowing indexing on a drive. If it's connected right now, it's
    /// processed immediately; otherwise it'll be handled on its next mount.
    func forgetAllowed(_ allowed: AllowedVolume) {
        saveAllowed(allowedVolumes.filter { $0.uuid != allowed.uuid })
        log("\"\(allowed.name)\" — no longer allowed to index")
        if let volume = connectedDrives.first(where: { $0.uuid == allowed.uuid }) {
            disableIndexing(volume)
        }
    }

    // MARK: - Cleanup

    func removeSpotlightIndex(_ volume: MountedVolume) {
        Task { await removeIndex(path: volume.path, name: volume.name, announce: true) }
    }

    private func removeIndex(path: String, name: String, announce: Bool) async {
        guard busyPaths.insert(path).inserted else { return }
        log("\"\(name)\" — removing old Spotlight index…")
        let result = await runInBackground { VolumeInspector.removeSpotlightIndex(volumePath: path) }
        busyPaths.remove(path)

        switch result {
        case .success(0):
            log("\"\(name)\" — no Spotlight index to remove")
            if announce { notify(name, "No Spotlight index to remove", .info) }
        case .success(let bytes):
            let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            log("\"\(name)\" — removed old Spotlight index, freed \(size) ✓", kind: .success)
            if announce { notify(name, "Removed Spotlight index · freed \(size)", .success) }
        case .failure(let error):
            log("\"\(name)\" — couldn't remove Spotlight index: \(error.message)", kind: .failure)
            if announce { notify(name, "Couldn't remove Spotlight index", .failure) }
        }
    }

    func removeClutter(_ volume: MountedVolume) {
        let path = volume.path, name = volume.name
        guard busyPaths.insert(path).inserted else { return }
        log("\"\(name)\" — removing macOS clutter (this can take a while on big drives)…")
        Task {
            let result = await runInBackground { VolumeInspector.removeClutter(volumePath: path) }
            busyPaths.remove(path)
            switch result {
            case .success(let report):
                let summary = "\(report.appleDoubleFiles) “._” and \(report.dsStoreFiles) .DS_Store files"
                log("\"\(name)\" — cleaned up \(summary) ✓", kind: .success)
                notify(name, "Cleaned up \(summary)", .success)
            case .failure(let error):
                log("\"\(name)\" — clutter cleanup failed: \(error.message)", kind: .failure)
                notify(name, "Clutter cleanup failed", .failure)
            }
        }
    }

    // MARK: - History

    private func addToHistory(name: String, path: String) {
        history.removeAll { $0.path == path }
        history.insert(DriveEntry(name: name, path: path), at: 0)
        if history.count > 100 { history = Array(history.prefix(100)) }
        saveHistory()
    }

    func removeEntry(_ entry: DriveEntry) { history.removeAll { $0.id == entry.id }; saveHistory() }
    func clearHistory() { history.removeAll(); saveHistory() }

    // MARK: - Persistence

    private func saveHistory() { Self.save(history, key: historyKey) }

    private func saveAllowed(_ volumes: [AllowedVolume]) {
        allowedVolumes = volumes
        Self.save(volumes, key: allowedKey)
    }

    private static func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    #if DEBUG
    /// Sample data for the screenshot generator.
    func loadScreenshotData(connected: [MountedVolume], allowed: [AllowedVolume], history: [DriveEntry]) {
        connectedDrives = connected
        allowedVolumes = allowed
        self.history = history
        isScanningVolumes = false
    }
    #endif

    // MARK: - Helpers

    private func log(_ message: String, kind: LogKind = .info) {
        LogStore.shared.log(message, kind: kind)
    }

    private func notify(_ title: String, _ subtitle: String, _ kind: Notice.Kind) {
        Notifier.shared.post(Notice(title: title, subtitle: subtitle, kind: kind))
    }
}
