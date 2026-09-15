import Foundation

/// Drives the `claude` CLI as a full coding agent inside one worktree, streaming what it does.
///
/// Deliberately the opposite of `InstalledCLIProvider`, which is the locked-down chat route: this
/// one grants every tool and many turns, which is only safe because the worktree is disposable.
struct AgentRunner: Sendable {
    let executable: URL
    let model: String
    let maxTurns: Int
    let environment: [String: String]

    static func resolve(model: String, maxTurns: Int) async throws -> AgentRunner {
        let kind = InstalledAIKind.claude
        guard
            let executable = await ExecutableLocator.locate(
                kind.command, extraHomePaths: kind.extraExecutablePaths)
        else {
            throw SubprocessRunner.Failure(
                reason: "Claude Code is not installed. See code.claude.com/docs to set it up.")
        }
        return AgentRunner(
            executable: executable, model: model, maxTurns: maxTurns,
            environment: SubprocessRunner.environment(
                prepending: [executable.deletingLastPathComponent().path]))
    }

    /// What a turn is allowed to do. A question may never write — that is the whole distinction.
    enum Mode: Sendable {
        case build
        case question

        /// Kept low for a question: an answer that needs forty turns is not an answer.
        var maxTurns: Int { self == .question ? 30 : 0 }
    }

    /// `session` resumes the previous attempt, so a retry keeps everything the first one worked out.
    func run(prompt: String, in worktree: URL, resuming session: String?, mode: Mode = .build)
        -> AsyncThrowingStream<AgentEvent, Error>
    {
        AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments(resuming: session, mode: mode)
            process.currentDirectoryURL = worktree
            process.environment = environment

            let stdin = Pipe()
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr

            let state = StreamState()
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                for event in state.decode(data) { continuation.yield(event) }
            }
            stderr.fileHandleForReading.readabilityHandler = { handle in
                state.absorbError(handle.availableData)
            }
            process.terminationHandler = { finished in
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                let trailing = (try? stdout.fileHandleForReading.readToEnd()) ?? Data()
                for event in state.decode(trailing) { continuation.yield(event) }
                for event in state.flush() { continuation.yield(event) }
                guard finished.terminationStatus == 0 || state.sawResult else {
                    continuation.finish(
                        throwing: SubprocessRunner.Failure(reason: state.failureReason))
                    return
                }
                continuation.finish()
            }

            do {
                try process.run()
            } catch {
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                process.terminationHandler = nil
                continuation.finish(throwing: error)
                return
            }

            continuation.onTermination = { reason in
                if case .cancelled = reason, process.isRunning { process.terminate() }
            }
            // A prompt past the pipe buffer blocks until the child drains it, so never inline.
            let input = stdin.fileHandleForWriting
            Task.detached {
                try? input.write(contentsOf: Data(prompt.utf8))
                try? input.close()
            }
        }
    }

    /// The CLI's own words when a stored session has aged out of `~/.claude` or was never there.
    static func isMissingSession(_ error: any Error) -> Bool {
        (error as? SubprocessRunner.Failure)?.reason.contains("No conversation found") == true
    }

    private func arguments(resuming session: String?, mode: Mode) -> [String] {
        var result = [
            "-p",
            "--model", model,
            "--output-format", "stream-json",
            "--verbose",
            "--permission-mode", "bypassPermissions",
            "--max-turns", String(mode == .question ? mode.maxTurns : maxTurns)
        ]
        if mode == .question {
            // Allowlist and denylist both: a question that can edit is a change nobody asked for.
            result += ["--allowedTools", "Read", "Grep", "Glob"]
            result += ["--disallowedTools", "Edit", "Write", "NotebookEdit", "Bash", "Task"]
        }
        if let session { result += ["--resume", session] }
        return result
    }
}

/// Touched from both pipe queues and the termination handler, so the lock is load-bearing.
private final class StreamState: @unchecked Sendable {
    private let lock = NSLock()
    private var decoder = AgentEventDecoder()
    private var errorOutput = Data()
    private var finished = false

    var sawResult: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }

    /// The tail of stderr, which is where the CLI puts the reason it refused to start at all.
    var failureReason: String {
        lock.lock()
        let text = String(decoding: errorOutput, as: UTF8.self)
        lock.unlock()
        let lines = text.split(whereSeparator: \.isNewline).suffix(4)
        let tail = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return tail.isEmpty ? "The agent exited without finishing." : tail
    }

    func decode(_ data: Data) -> [AgentEvent] {
        guard !data.isEmpty else { return [] }
        lock.lock()
        let events = decoder.push(data)
        note(events)
        lock.unlock()
        return events
    }

    func flush() -> [AgentEvent] {
        lock.lock()
        let events = decoder.finish()
        note(events)
        lock.unlock()
        return events
    }

    func absorbError(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        errorOutput.append(data)
        lock.unlock()
    }

    /// Called with the lock held.
    private func note(_ events: [AgentEvent]) {
        if events.contains(where: { if case .finished = $0 { true } else { false } }) {
            finished = true
        }
    }
}
