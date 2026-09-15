import Foundation

/// Runs one build-or-git tool to completion in a directory. Drained as it arrives, so no tool wedges.
enum SubprocessRunner {
    struct Result: Sendable {
        let status: Int32
        let output: String

        var succeeded: Bool { status == 0 }
    }

    struct Failure: LocalizedError {
        let reason: String

        var errorDescription: String? { reason }
    }

    /// A clean build of this app runs into the minutes, so the ceiling is a wedge check, not a budget.
    static func run(
        _ executable: URL, _ arguments: [String], in directory: URL,
        environment: [String: String], timeout: Duration = .seconds(1800)
    ) async throws -> Result {
        let handle = ProcessHandle()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                process.currentDirectoryURL = directory
                process.environment = environment
                process.standardInput = FileHandle.nullDevice

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                let collector = OutputCollector()
                pipe.fileHandleForReading.readabilityHandler = { collector.absorb($0.availableData) }

                process.terminationHandler = { finished in
                    pipe.fileHandleForReading.readabilityHandler = nil
                    collector.absorb((try? pipe.fileHandleForReading.readToEnd()) ?? Data())
                    continuation.resume(
                        returning: Result(
                            status: finished.terminationStatus, output: collector.text))
                }
                do {
                    try process.run()
                } catch {
                    // The handler never fires for a process that never started, so resume here.
                    pipe.fileHandleForReading.readabilityHandler = nil
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                    return
                }
                handle.adopt(process)
                Task {
                    try? await Task.sleep(for: timeout)
                    handle.terminate()
                }
            }
        } onCancel: {
            handle.terminate()
        }
    }

    /// Finder hands the app its own stripped PATH, so every tool a run needs is put back by hand.
    static func environment(prepending paths: [String] = []) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let known = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let existing = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var ordered: [String] = []
        for path in paths + known + existing where !path.isEmpty && !ordered.contains(path) {
            ordered.append(path)
        }
        environment["PATH"] = ordered.joined(separator: ":")
        // `xcode-select` commonly points at CommandLineTools, which cannot build an app target.
        if environment["DEVELOPER_DIR"] == nil, let developer = xcodeDeveloperDirectory {
            environment["DEVELOPER_DIR"] = developer
        }
        return environment
    }

    private static var xcodeDeveloperDirectory: String? {
        let path = "/Applications/Xcode.app/Contents/Developer"
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }
}

/// Shared between the cancellation handler and the watchdog, so the lock is load-bearing.
private final class ProcessHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func adopt(_ process: Process) {
        lock.lock()
        let alreadyCancelled = cancelled
        self.process = process
        lock.unlock()
        if alreadyCancelled { terminate() }
    }

    func terminate() {
        lock.lock()
        cancelled = true
        let process = self.process
        lock.unlock()
        guard let process, process.isRunning else { return }
        process.terminate()
    }
}

/// Read from the pipe's queue and the termination handler, so the lock is load-bearing.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        // Latin-1 cannot fail, so a tool emitting other encodings still reaches the user.
        return String(bytes: buffer, encoding: .utf8)
            ?? String(bytes: buffer, encoding: .isoLatin1) ?? ""
    }

    /// Buffers bytes, not text: a read landing mid-character would decode to a replacement.
    func absorb(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        buffer.append(data)
        lock.unlock()
    }
}
