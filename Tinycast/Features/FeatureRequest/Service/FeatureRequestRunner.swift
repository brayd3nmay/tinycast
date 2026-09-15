import Foundation

/// Carries one request from typed sentence to open pull request, retrying against the gates.
///
/// Every step happens in a throwaway worktree under Application Support, so the checkout the user
/// works in is never touched — not by the agent, not by a failed build, not by a retry.
struct FeatureRequestRunner: Sendable {
    struct Configuration: Sendable {
        let repository: URL
        let baseBranch: String
        let model: String
        let maxAttempts: Int
        let maxTurns: Int
        let opensPullRequest: Bool
    }

    /// Everything the run tells the coordinator while it is still running.
    enum Progress: Sendable {
        case status(FeatureRequestStatus)
        /// Carried out so a follow-up days later still resumes the session that built the branch.
        case session(String)
        case activity(String)
        case attempt(FeatureRequest.Attempt)
        case worktree(URL)
    }

    let configuration: Configuration
    let report: @Sendable (Progress) -> Void

    /// `change` is non-nil for a follow-up: same branch, same session, same pull request.
    func run(_ request: FeatureRequest, change: String? = nil) async throws -> URL? {
        guard GitRunner.isTinycastCheckout(configuration.repository) else {
            throw SubprocessRunner.Failure(
                reason: "\(configuration.repository.lastPathComponent) is not a Tinycast checkout.")
        }
        report(.status(.preparing))
        let git = try await GitRunner.resolve(repository: configuration.repository)
        let agent = try await AgentRunner.resolve(
            model: configuration.model, maxTurns: configuration.maxTurns)

        await git.fetch()
        let worktree = Self.worktreeURL(for: request)
        try FileManager.default.createDirectory(
            at: worktree.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: worktree)
        if change == nil {
            let base = await git.baseRef(configuration.baseBranch)
            try await git.addWorktree(at: worktree, branch: request.branch, base: base)
        } else {
            try await git.reopenWorktree(at: worktree, branch: request.branch)
        }
        report(.worktree(worktree))

        do {
            let verified = try await build(
                request, change: change, agent: agent, git: git, worktree: worktree)
            // Before publishing: the gate's app is the only copy, and the next run overwrites it.
            try? PreviewBuild.preserve(from: Self.derivedDataURL, for: request.shortID)
            let url = try await publish(
                request, report: verified, git: git, worktree: worktree, isFollowUp: change != nil)
            // Only on success: a failed run's worktree is the only copy of what the agent wrote.
            await git.removeWorktree(at: worktree, branch: request.branch)
            return url
        } catch is CancellationError {
            await git.removeWorktree(at: worktree, branch: request.branch)
            throw CancellationError()
        }
    }

    // MARK: - Implement and verify

    private func build(
        _ request: FeatureRequest, change: String?, agent: AgentRunner, git: GitRunner,
        worktree: URL
    ) async throws -> VerificationReport {
        let verifier = await VerificationRunner.resolve(
            worktree: worktree, derivedData: Self.derivedDataURL)
        var session = request.sessionID
        var previous: VerificationReport?

        for attempt in 1...configuration.maxAttempts {
            try Task.checkCancellation()
            report(.status(.implementing(attempt: attempt)))
            let prompt = prompt(for: request, change: change, attempt: attempt, after: previous)
            let result = try await drive(agent, prompt: prompt, in: worktree, resuming: &session)

            let changes = WorktreeChange.parse(
                porcelain: try await git.porcelain(in: worktree))
            if let id = session { report(.session(id)) }
            guard !changes.isEmpty else {
                throw SubprocessRunner.Failure(
                    reason: "The agent changed nothing. It said: " + result.summary)
            }

            let verified = try await verifier.run(
                changes: changes, numstat: try await git.numstat(in: worktree)
            ) { step in
                report(.status(.verifying(attempt: attempt, step: step)))
            }
            report(
                .attempt(
                    FeatureRequest.Attempt(
                        id: attempt, summary: result.summary, changedFiles: changes.count,
                        report: verified)))
            if verified.passed { return verified }
            previous = verified
        }
        throw SubprocessRunner.Failure(
            reason: "Still failing after \(configuration.maxAttempts) attempts — "
                + (previous?.failure?.step.title ?? "verification") + ".")
    }

    private func prompt(
        for request: FeatureRequest, change: String?, attempt: Int, after previous: VerificationReport?
    ) -> String {
        if let previous, attempt > 1 {
            return FeatureRequestPrompt.retry(
                request, report: previous, attempt: attempt, of: configuration.maxAttempts)
        }
        guard let change else { return FeatureRequestPrompt.initial(request) }
        return FeatureRequestPrompt.followUp(request, change: change)
    }

    /// Resuming the same session is what makes a retry a correction rather than a second guess.
    private func drive(
        _ agent: AgentRunner, prompt: String, in worktree: URL, resuming session: inout String?
    ) async throws -> AgentEvent.Result {
        do {
            return try await turn(agent, prompt: prompt, in: worktree, resuming: &session)
        } catch where AgentRunner.isMissingSession(error) {
            // The branch still holds the work and the prompt still describes it, so start fresh.
            session = nil
            return try await turn(agent, prompt: prompt, in: worktree, resuming: &session)
        }
    }

    private func turn(
        _ agent: AgentRunner, prompt: String, in worktree: URL, resuming session: inout String?
    ) async throws -> AgentEvent.Result {
        var outcome: AgentEvent.Result?
        for try await event in agent.run(prompt: prompt, in: worktree, resuming: session) {
            switch event {
            case .started(let id): session = id
            case .activity(let line), .narration(let line): report(.activity(line))
            case .finished(let result):
                outcome = result
                if let id = result.sessionID { session = id }
            }
        }
        try Task.checkCancellation()
        guard let outcome else {
            throw SubprocessRunner.Failure(reason: "The agent exited without finishing.")
        }
        // A turn-limited or errored run still leaves work behind, so the gates judge it as usual.
        return outcome
    }

    // MARK: - Publish

    private func publish(
        _ request: FeatureRequest, report verified: VerificationReport, git: GitRunner,
        worktree: URL, isFollowUp: Bool
    ) async throws -> URL? {
        report(.status(.publishing))
        let subject =
            isFollowUp
            ? FeatureBranch.title(prompt: request.followUps.last ?? "Apply requested change")
            : FeatureBranch.commitMessage(prompt: request.prompt)
        try await git.commitAll(in: worktree, message: subject)
        try await git.push(branch: request.branch, from: worktree)
        // The pull request is already open on this branch; the push is what updates it.
        if isFollowUp { return request.pullRequestURL }
        guard configuration.opensPullRequest else { return nil }
        return try await git.openPullRequest(
            from: worktree, base: configuration.baseBranch,
            title: FeatureBranch.title(prompt: request.prompt),
            body: FeatureBranch.body(request: request, report: verified))
    }

    // MARK: - Locations

    /// Application Support, not caches: a failed run's worktree must survive until the user looks.
    static func worktreeURL(for request: FeatureRequest) -> URL {
        AppPaths.applicationSupport()
            .appending(path: "feature-requests")
            .appending(path: request.shortID)
    }

    /// Shared across runs on purpose — a cold build of this app is minutes the retry loop can keep.
    static var derivedDataURL: URL {
        AppPaths.caches().appending(path: "feature-request-build")
    }
}
