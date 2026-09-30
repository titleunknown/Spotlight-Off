import Foundation

enum VolumeClassification: Equatable, Sendable {
    case notExternal
    case diskImage
    case timeMachine
    case eligible(name: String, uuid: String?)
}

enum DisableOutcome: Equatable, Sendable {
    case gone, unreadable, unexpected, alreadyOff, disabled
    case failed(String)
}

struct MdutilResult: Sendable {
    let succeeded: Bool
    let detail: String
}

struct CleanupError: Error, Sendable {
    let message: String
}

struct ClutterReport: Equatable, Sendable {
    let appleDoubleFiles: Int
    let dsStoreFiles: Int
}

/// Volume classification, `mdutil` control and drive cleanup.
///
/// The parsing helpers are pure; everything else is thread-safe but blocking
/// (it spawns subprocesses or walks the file system), so call it off the main
/// thread — see `runInBackground`.
enum VolumeInspector {

    // MARK: - Eligibility

    static let eligibilityKeys: Set<URLResourceKey> = [
        .volumeIsRootFileSystemKey, .volumeIsInternalKey, .volumeIsLocalKey,
        .volumeIsRemovableKey, .volumeIsEjectableKey
    ]

    /// A volume is eligible if it's local, not the boot volume, and either on an
    /// external bus or removable media. The removable check matters for the
    /// MacBook's built-in SD card reader: it sits on an internal bus, so cards in
    /// it report `volumeIsInternal == true` even though they're removable.
    static func isEligible(isLocal: Bool, isRoot: Bool, isInternal: Bool,
                           isRemovable: Bool, isEjectable: Bool) -> Bool {
        isLocal && !isRoot && (!isInternal || isRemovable || isEjectable)
    }

    static func isEligible(_ vals: URLResourceValues) -> Bool {
        isEligible(isLocal:     vals.volumeIsLocal          ?? false,
                   isRoot:      vals.volumeIsRootFileSystem ?? false,
                   isInternal:  vals.volumeIsInternal       ?? false,
                   isRemovable: vals.volumeIsRemovable      ?? false,
                   isEjectable: vals.volumeIsEjectable      ?? false)
    }

    static func isExternalVolume(_ url: URL) -> Bool {
        guard let vals = try? url.resourceValues(forKeys: eligibilityKeys) else {
            LogStore.shared.log("Could not read volume flags for \(url.path)", kind: .failure)
            return false
        }
        return isEligible(vals)
    }

    // MARK: - mdutil Output Parsing

    /// `mdutil` first echoes the volume's *resolved* path on its own line
    /// (e.g. "/System/Volumes/Data/Volumes/<name>:"), so that line is dropped
    /// before matching — otherwise a drive named "Disabled" reads as disabled.
    static func mdutilBody(_ output: String) -> String {
        let lines = output.split(whereSeparator: \.isNewline)
        let hasHeader = lines.count > 1
            && lines[0].trimmingCharacters(in: .whitespaces).hasSuffix(":")
        let body = hasHeader ? lines.dropFirst() : lines[...]
        return body.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Parses `mdutil -s` output. Returns nil when the path couldn't be read.
    static func parseIndexingState(_ output: String) -> IndexingState? {
        let body = mdutilBody(output)
        // One-line errors echo the path, so they're checked before state words.
        if body.contains("could not") || body.contains("no such") || body.contains("invalid path") {
            return nil
        }
        if body.contains("disabled")   { return .disabled }
        if body.contains("enabled")    { return .enabled }
        if body.contains("unexpected") { return .unexpected }
        return .unknown
    }

    /// `mdutil -i` can exit 0 while still failing (it even prints "Must be root
    /// to run this command" with status 0), so the output is checked as well.
    static func mdutilSucceeded(status: Int32, output: String) -> Bool {
        let body = mdutilBody(output)
        return status == 0 && !body.contains("error:") && !body.contains("must be root")
    }

    // MARK: - Plist Parsing

    /// Mount points of attached disk images, from `hdiutil info -plist`.
    static func diskImageMountPoints(fromHdiutilPlist data: Data) -> Set<String> {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let images = plist["images"] as? [[String: Any]]
        else { return [] }
        var points = Set<String>()
        for image in images {
            for entity in image["system-entities"] as? [[String: Any]] ?? [] {
                if let mountPoint = entity["mount-point"] as? String { points.insert(mountPoint) }
            }
        }
        return points
    }

    /// Mount points of Time Machine destinations, from `tmutil destinationinfo -X`.
    static func timeMachineMountPoints(fromTmutilPlist data: Data) -> Set<String> {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let destinations = plist["Destinations"] as? [[String: Any]]
        else { return [] }
        return Set(destinations.compactMap { $0["MountPoint"] as? String })
    }

    // MARK: - Probes (blocking)

    private static func diskImageMountPoints() -> Set<String> {
        guard let result = try? ProcessRunner.run("/usr/bin/hdiutil", ["info", "-plist"]) else { return [] }
        return diskImageMountPoints(fromHdiutilPlist: Data(result.stdout.utf8))
    }

    private static func timeMachineMountPoints() -> Set<String> {
        guard let result = try? ProcessRunner.run("/usr/bin/tmutil", ["destinationinfo", "-X"]) else { return [] }
        return timeMachineMountPoints(fromTmutilPlist: Data(result.stdout.utf8))
    }

    private static func isTimeMachineVolume(_ path: String, destinations: Set<String>) -> Bool {
        if path.contains("/.timemachine") { return true }
        let backupDB = (path as NSString).appendingPathComponent("Backups.backupdb")
        if FileManager.default.fileExists(atPath: backupDB) { return true }
        return destinations.contains(path)
    }

    static func volumeUUID(_ path: String) -> String? {
        try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
    }

    static func volumeName(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let name = (try? url.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? ""
        if !name.isEmpty { return name }
        return url.lastPathComponent.isEmpty ? "External Drive" : url.lastPathComponent
    }

    static func mountedVolumePaths() -> [String] {
        (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil,
                                               options: [.skipHiddenVolumes]) ?? []).map(\.path)
    }

    /// Decides whether Spotlight Off should manage a mounted volume. Shared by
    /// mount handling and the connected-drives scan so they always agree.
    /// The cheap metadata check runs first so internal mounts never spawn hdiutil.
    static func classify(path: String) -> VolumeClassification {
        guard isExternalVolume(URL(fileURLWithPath: path)) else { return .notExternal }
        if diskImageMountPoints().contains(path) { return .diskImage }
        if isTimeMachineVolume(path, destinations: timeMachineMountPoints()) { return .timeMachine }
        return .eligible(name: volumeName(path), uuid: volumeUUID(path))
    }

    static func indexingState(path: String) -> IndexingState? {
        do {
            let result = try ProcessRunner.run("/usr/bin/mdutil", ["-s", path])
            if result.timedOut {
                LogStore.shared.log("mdutil -s timed out for \(path)", kind: .failure)
                return nil
            }
            return parseIndexingState(result.stdout + result.stderr)
        } catch {
            LogStore.shared.log("mdutil -s error: \(error.localizedDescription)", kind: .failure)
            return nil
        }
    }

    /// Runs `mdutil -i on|off`.
    static func setIndexing(path: String, enabled: Bool) -> MdutilResult {
        do {
            let result = try ProcessRunner.run("/usr/bin/mdutil", ["-i", enabled ? "on" : "off", path], timeout: 60)
            if result.timedOut { return MdutilResult(succeeded: false, detail: "mdutil timed out") }
            let ok = mdutilSucceeded(status: result.status, output: result.stdout + result.stderr)
            let detail = result.combined.isEmpty ? "exit \(result.status)" : result.combined
            return MdutilResult(succeeded: ok, detail: ok ? "" : detail)
        } catch {
            return MdutilResult(succeeded: false, detail: error.localizedDescription)
        }
    }

    /// Checks the volume is still there, reads its state and turns indexing off if needed.
    static func disableIfNeeded(path: String) -> DisableOutcome {
        guard FileManager.default.fileExists(atPath: path) else { return .gone }
        switch indexingState(path: path) {
        case nil:         return .unreadable
        case .disabled:   return .alreadyOff
        case .unexpected: return .unexpected
        case .enabled, .unknown:
            let result = setIndexing(path: path, enabled: false)
            return result.succeeded ? .disabled : .failed(result.detail)
        }
    }

    /// Every mounted volume Spotlight Off manages, with its indexing state.
    static func scanConnectedDrives() -> [MountedVolume] {
        let keys = eligibilityKeys.union([.volumeIsBrowsableKey])
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        let candidates = urls.filter { url in
            guard let vals = try? url.resourceValues(forKeys: keys) else { return false }
            return (vals.volumeIsBrowsable ?? true) && isEligible(vals)
        }
        guard !candidates.isEmpty else { return [] }

        // One hdiutil and one tmutil call for the whole scan.
        let diskImages = diskImageMountPoints()
        let timeMachine = timeMachineMountPoints()
        return candidates
            .map(\.path)
            .filter { !diskImages.contains($0) && !isTimeMachineVolume($0, destinations: timeMachine) }
            .map { MountedVolume(name: volumeName($0), path: $0, uuid: volumeUUID($0),
                                 indexing: indexingState(path: $0)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Cleanup (blocking)

    /// Folders macOS manages itself; never walked or touched by clutter cleanup.
    private static let systemFolders: Set<String> = [
        ".Spotlight-V100", ".fseventsd", ".Trashes", ".DocumentRevisions-V100",
        ".TemporaryItems", ".MobileBackups"
    ]

    /// Deletes the `.Spotlight-V100` index macOS built before indexing was turned
    /// off. `mdutil -X` would be cleaner but requires root, so the folder is
    /// removed directly — external drives normally ignore ownership, which makes
    /// it deletable. Returns the bytes freed (0 when there was no index).
    static func removeSpotlightIndex(volumePath: String) -> Result<Int64, CleanupError> {
        if indexingState(path: volumePath) == .enabled {
            return .failure(CleanupError(message: "Spotlight indexing is on for this drive, so macOS would rebuild the index. Turn indexing off first."))
        }
        let index = URL(fileURLWithPath: volumePath).appendingPathComponent(".Spotlight-V100")
        guard FileManager.default.fileExists(atPath: index.path) else { return .success(0) }
        let size = allocatedSize(of: index)
        do {
            try FileManager.default.removeItem(at: index)
            return .success(size)
        } catch {
            return .failure(CleanupError(message: "macOS didn't allow removing the index: \(error.localizedDescription)"))
        }
    }

    /// Removes `._` AppleDouble files (via `dot_clean -m`, which merges them back
    /// into native metadata where the file system supports it) and `.DS_Store`
    /// files across the whole drive.
    static func removeClutter(volumePath: String) -> Result<ClutterReport, CleanupError> {
        let root = URL(fileURLWithPath: volumePath)
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil, options: [],
            errorHandler: { _, _ in true })
        else { return .failure(CleanupError(message: "Couldn't read the drive.")) }

        var appleDouble = 0
        var dsStores: [URL] = []
        for case let url as URL in walker {
            let name = url.lastPathComponent
            if systemFolders.contains(name) { walker.skipDescendants(); continue }
            if name == ".DS_Store" { dsStores.append(url) }
            else if name.hasPrefix("._") { appleDouble += 1 }
        }

        if appleDouble > 0 {
            do {
                let result = try ProcessRunner.run("/usr/sbin/dot_clean", ["-m", volumePath], timeout: 1800)
                if result.timedOut || result.status != 0 {
                    let detail = result.timedOut ? "timed out" : (result.combined.isEmpty ? "exit \(result.status)" : result.combined)
                    return .failure(CleanupError(message: "dot_clean failed: \(detail)"))
                }
            } catch {
                return .failure(CleanupError(message: "dot_clean failed: \(error.localizedDescription)"))
            }
        }

        let removedStores = dsStores.filter { (try? FileManager.default.removeItem(at: $0)) != nil }.count
        return .success(ClutterReport(appleDoubleFiles: appleDouble, dsStoreFiles: removedStores))
    }

    private static func allocatedSize(of folder: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey]
        guard let walker = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: Array(keys), options: [],
            errorHandler: { _, _ in true })
        else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            total += Int64((try? url.resourceValues(forKeys: keys))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
