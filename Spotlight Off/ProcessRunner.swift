import Foundation

struct ProcessResult: Sendable {
    let status: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool

    var combined: String { (stdout + stderr).trimmingCharacters(in: .whitespacesAndNewlines) }
}

enum ProcessRunner {
    /// Runs a command and waits for it. Blocking — call off the main thread.
    ///
    /// stdout and stderr are drained concurrently while the process runs, so
    /// output larger than the pipe buffer can't deadlock, and the process is
    /// terminated if it outlives `timeout` (e.g. `mdutil` on a failing drive).
    static func run(_ executable: String, _ arguments: [String],
                    timeout: TimeInterval = 30) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError  = errPipe
        try process.run()

        let out = DataBox(), err = DataBox()
        let group = DispatchGroup()
        for (handle, box) in [(outPipe.fileHandleForReading, out), (errPipe.fileHandleForReading, err)] {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                box.data = handle.readDataToEndOfFile()
                group.leave()
            }
        }

        var timedOut = false
        if group.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            _ = group.wait(timeout: .now() + 2)
        }
        process.waitUntilExit()

        return ProcessResult(
            status: process.terminationStatus,
            stdout: String(data: out.data, encoding: .utf8) ?? "",
            stderr: String(data: err.data, encoding: .utf8) ?? "",
            timedOut: timedOut)
    }

    /// Only ever written by one reader thread, then read after `group.wait`.
    private final class DataBox: @unchecked Sendable {
        var data = Data()
    }
}

/// Runs blocking work (subprocesses, file walks) on a GCD queue so it never
/// occupies Swift's cooperative thread pool or the main thread.
func runInBackground<T: Sendable>(_ qos: DispatchQoS.QoSClass = .utility,
                                  _ work: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: qos).async { continuation.resume(returning: work()) }
    }
}
