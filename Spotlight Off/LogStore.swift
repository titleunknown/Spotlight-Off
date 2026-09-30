import Foundation
import Combine

enum LogKind: String, Sendable { case info, success, failure }

struct LogEntry: Identifiable, Equatable, Sendable {
    let id = UUID()
    let date: Date
    let message: String
    let kind: LogKind

    /// Time only for today's entries; entries restored from earlier days get a date too.
    var timestamp: String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .standard)
            : date.formatted(date: .abbreviated, time: .standard)
    }

    static func == (a: LogEntry, b: LogEntry) -> Bool {
        a.date == b.date && a.message == b.message && a.kind == b.kind
    }
}

/// The activity log: the latest entries in memory for the UI, and every entry
/// appended to ~/Library/Logs/Spotlight Off/activity.log so it survives relaunches.
///
/// `log` is callable from any thread. `entries` is only mutated on the main
/// queue, and file I/O happens on a private serial queue — hence the
/// `@unchecked Sendable`.
final class LogStore: ObservableObject, @unchecked Sendable {
    static let shared = LogStore()
    static let maxEntries = 200
    /// The file is trimmed back to `keepLinesOnTrim` lines once it grows past this.
    static let maxFileBytes = 1_000_000
    static let keepLinesOnTrim = 2_000

    @Published private(set) var entries: [LogEntry]
    let fileURL: URL
    private let fileQueue = DispatchQueue(label: "spotlightoff.log-file")

    init(fileURL: URL = LogStore.defaultFileURL) {
        self.fileURL = fileURL
        self.entries = Self.loadRecent(from: fileURL)
    }

    static var defaultFileURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Spotlight Off/activity.log")
    }

    /// Safe to call from any thread.
    func log(_ message: String, kind: LogKind = .info) {
        let entry = LogEntry(date: Date(), message: message, kind: kind)
        print("[\(entry.timestamp)] \(message)")
        let url = fileURL
        fileQueue.async { Self.append(entry, to: url) }
        DispatchQueue.main.async {
            self.entries.append(entry)
            if self.entries.count > Self.maxEntries { self.entries.removeFirst() }
        }
    }

    @MainActor func clear() {
        entries.removeAll()
        let url = fileURL
        fileQueue.async { try? Data().write(to: url) }
    }

    // MARK: - File Format
    // One entry per line: ISO-8601 date, kind and message separated by tabs.

    static func encodeLine(_ entry: LogEntry) -> String {
        let message = entry.message
            .replacingOccurrences(of: "\t", with: " ")
            .components(separatedBy: .newlines).joined(separator: " ⏎ ")
        return "\(entry.date.ISO8601Format())\t\(entry.kind.rawValue)\t\(message)"
    }

    static func decodeLine(_ line: String) -> LogEntry? {
        let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3,
              let date = try? Date(String(parts[0]), strategy: .iso8601),
              let kind = LogKind(rawValue: String(parts[1]))
        else { return nil }
        return LogEntry(date: date, message: String(parts[2]), kind: kind)
    }

    private static func loadRecent(from url: URL) -> [LogEntry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline)
            .suffix(maxEntries)
            .compactMap { decodeLine(String($0)) }
    }

    private static func append(_ entry: LogEntry, to url: URL) {
        let fm = FileManager.default
        let line = Data((encodeLine(entry) + "\n").utf8)
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? line.write(to: url)
            return
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return }
        try? handle.write(contentsOf: line)

        if size > UInt64(maxFileBytes), let text = try? String(contentsOf: url, encoding: .utf8) {
            let kept = text.split(whereSeparator: \.isNewline).suffix(keepLinesOnTrim)
            try? Data((kept.joined(separator: "\n") + "\n").utf8).write(to: url)
        }
    }
}
