import Foundation

/// Every git and `gh` call a run makes. The agent never touches the checkout the user works in.
struct GitRunner: Sendable {
    let git: URL
    let gh: URL?
    let repository: URL
    let environment: [String: String]

    static func resolve(repository: URL) async throws -> GitRunner {
        guard let git = await ExecutableLocator.locate("git") else {
            throw SubprocessRunner.Failure(reason: "git is not installed.")
        }
        let gh = await ExecutableLocator.locate("gh")
        let extraPaths = [git, gh].compactMap { $0?.deletingLastPathComponent().path }
        var environment = SubprocessRunner.environment(prepending: extraPaths)
        // Nothing can answer a prompt here, so `gh` must fail out rather than wait for the timeout.
        environment["GH_PROMPT_DISABLED"] = "1"
        environment["GH_NO_UPDATE_NOTIFIER"] = "1"
        return GitRunner(git: git, gh: gh, repository: repository, environment: environment)
    }

    /// The one shape this feature builds for, checked before a run rather than after it fails.
    static func isTinycastCheckout(_ url: URL) -> Bool {
        let manager = FileManager.default
        return ["AGENTS.md", "project.yml", "Scripts/run-tests.sh"].allSatisfy {
            manager.fileExists(atPath: url.appending(path: $0).path)
        }
    }

    // MARK: - Worktrees

    /// `origin/<base>` when it resolves: branching off a stale local `main` reopens merged work.
    func baseRef(_ base: String) async -> String {
        let remote = "origin/" + base
        let probe = try? await run(["rev-parse", "--verify", "--quiet", remote], in: repository)
        return probe?.succeeded == true ? remote : base
    }

    /// Best effort: a run offline should still build against whatever the last fetch left behind.
    func fetch() async {
        _ = try? await run(["fetch", "--quiet", "origin"], in: repository, timeout: .seconds(120))
    }

    func addWorktree(at path: URL, branch: String, base: String) async throws {
        let result = try await run(
            ["worktree", "add", "--quiet", "-b", branch, path.path, base], in: repository)
        guard result.succeeded else {
            throw SubprocessRunner.Failure(
                reason: "Could not create a worktree: " + tail(result.output))
        }
    }

    /// `-B`, because a successful run deletes its local branch — the remote is the surviving copy.
    func reopenWorktree(at path: URL, branch: String) async throws {
        let result = try await run(
            ["worktree", "add", "--quiet", "-B", branch, path.path, "origin/" + branch],
            in: repository)
        guard result.succeeded else {
            throw SubprocessRunner.Failure(
                reason: "Could not check out \(branch): " + tail(result.output))
        }
    }

    /// Detached: a question never commits, so it needs no branch of its own to commit onto.
    func readOnlyWorktree(at path: URL, branch: String) async throws {
        let result = try await run(
            ["worktree", "add", "--quiet", "--detach", path.path, "origin/" + branch],
            in: repository)
        guard result.succeeded else {
            throw SubprocessRunner.Failure(
                reason: "Could not read \(branch): " + tail(result.output))
        }
    }

    /// No branch to delete, unlike `removeWorktree`, because a detached checkout never made one.
    func discardWorktree(at path: URL) async {
        _ = try? await run(["worktree", "remove", "--force", path.path], in: repository)
        try? FileManager.default.removeItem(at: path)
    }

    /// Takes the branch with it: a failed run should leave nothing for the next one to collide with.
    func removeWorktree(at path: URL, branch: String) async {
        _ = try? await run(["worktree", "remove", "--force", path.path], in: repository)
        _ = try? await run(["branch", "-D", branch], in: repository)
        try? FileManager.default.removeItem(at: path)
    }

    // MARK: - The change

    /// Raw, so `WorktreeChange` stays the one place that knows the porcelain format.
    func porcelain(in worktree: URL) async throws -> String {
        let result = try await run(["status", "--porcelain"], in: worktree)
        guard result.succeeded else {
            throw SubprocessRunner.Failure(reason: "Could not read the worktree's status.")
        }
        return result.output
    }

    /// `-M` so a rename reads as one edit rather than as a whole file deleted and another added.
    func numstat(in worktree: URL) async throws -> String {
        let result = try await run(["diff", "--numstat", "-M", "HEAD"], in: worktree)
        guard result.succeeded else {
            throw SubprocessRunner.Failure(reason: "Could not read the worktree's line counts.")
        }
        return result.output
    }

    func commitAll(in worktree: URL, message: String) async throws {
        let staged = try await run(["add", "-A"], in: worktree)
        guard staged.succeeded else {
            throw SubprocessRunner.Failure(reason: "Could not stage the change: " + tail(staged.output))
        }
        let committed = try await run(["commit", "-m", message], in: worktree)
        guard committed.succeeded else {
            throw SubprocessRunner.Failure(
                reason: "Could not commit the change: " + tail(committed.output))
        }
    }

    func push(branch: String, from worktree: URL) async throws {
        let result = try await run(
            ["push", "--quiet", "-u", "origin", branch], in: worktree, timeout: .seconds(300))
        guard result.succeeded else {
            throw SubprocessRunner.Failure(reason: "Could not push \(branch): " + tail(result.output))
        }
    }

    /// Run from inside the worktree so `gh` resolves the repository the same way the user's shell does.
    func openPullRequest(from worktree: URL, base: String, title: String, body: String) async throws
        -> URL
    {
        guard let gh else {
            throw SubprocessRunner.Failure(
                reason: "The GitHub CLI is not installed, so the branch was pushed but no pull "
                    + "request was opened.")
        }
        // No `--head`: run from the worktree and `gh` reads the branch that is checked out there.
        let result = try await SubprocessRunner.run(
            gh, ["pr", "create", "--base", base, "--title", title, "--body", body],
            in: worktree, environment: environment, timeout: .seconds(180))
        guard result.succeeded, let url = Self.pullRequestURL(in: result.output) else {
            throw SubprocessRunner.Failure(
                reason: "Could not open the pull request: " + tail(result.output))
        }
        return url
    }

    /// `gh` prints progress lines around the URL, so the URL is found rather than assumed last.
    static func pullRequestURL(in output: String) -> URL? {
        for line in output.split(whereSeparator: \.isWhitespace).reversed() {
            let candidate = String(line)
            guard candidate.hasPrefix("https://"), candidate.contains("/pull/") else { continue }
            return URL(string: candidate)
        }
        return nil
    }

    // MARK: - Plumbing

    private func run(
        _ arguments: [String], in directory: URL, timeout: Duration = .seconds(120)
    ) async throws -> SubprocessRunner.Result {
        try await SubprocessRunner.run(
            git, arguments, in: directory, environment: environment, timeout: timeout)
    }

    private func tail(_ output: String) -> String {
        let lines = output.split(whereSeparator: \.isNewline).suffix(4)
        let text = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "no output" : text
    }
}
