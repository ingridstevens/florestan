import Foundation

/// Runs command-line tools (yt-dlp, brew, osascript) and streams their output.
enum Shell {
    struct Result {
        var status: Int32
        var stdout: String
        var stderr: String
        var succeeded: Bool { status == 0 }
    }

    static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]

    static func locate(_ tool: String) -> URL? {
        searchPaths.lazy
            .map { URL(fileURLWithPath: $0).appendingPathComponent(tool) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Runs a tool and collects its output. `onLine` receives each stdout line as it arrives.
    /// Cancelling the calling task terminates the process.
    static func run(_ executable: URL, _ arguments: [String], onLine: (@Sendable (String) -> Void)? = nil) async throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (searchPaths + [env["PATH"] ?? ""]).joined(separator: ":")
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        process.environment = env

        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let collector = OutputCollector(onLine: onLine)
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            collector.appendOut(handle.availableData)
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            collector.appendErr(handle.availableData)
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Result, Error>) in
                process.terminationHandler = { p in
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    collector.appendOut(outPipe.fileHandleForReading.readDataToEndOfFile())
                    collector.appendErr(errPipe.fileHandleForReading.readDataToEndOfFile())
                    continuation.resume(returning: collector.result(status: p.terminationStatus))
                }
                do { try process.run() } catch { continuation.resume(throwing: error) }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data(), err = Data(), pending = Data()
    private let onLine: (@Sendable (String) -> Void)?

    init(onLine: (@Sendable (String) -> Void)?) { self.onLine = onLine }

    func appendOut(_ data: Data) {
        guard !data.isEmpty else { return }
        var lines: [String] = []
        lock.withLock {
            out.append(data)
            pending.append(data)
            while let nl = pending.firstIndex(of: 0x0A) {
                lines.append(String(decoding: pending[pending.startIndex..<nl], as: UTF8.self))
                pending.removeSubrange(pending.startIndex...nl)
            }
        }
        lines.forEach { onLine?($0) }
    }

    func appendErr(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.withLock { err.append(data) }
    }

    func result(status: Int32) -> Shell.Result {
        lock.withLock {
            Shell.Result(status: status, stdout: String(decoding: out, as: UTF8.self), stderr: String(decoding: err, as: UTF8.self))
        }
    }
}
