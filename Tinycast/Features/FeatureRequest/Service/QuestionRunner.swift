import Foundation

/// Answers a question about a request's branch without being able to change it.
///
/// The worktree is kept for the life of the conversation rather than cut per question: a checkout
/// per turn would make "where does this go" cost more than the answer is worth.
struct QuestionRunner: Sendable {
    let configuration: FeatureRequestRunner.Configuration
    let report: @Sendable (AgentEvent) -> Void

    /// Answers from the files on the branch, not from what the session happens to remember.
    func ask(_ question: String, for request: FeatureRequest) async throws -> AgentEvent.Result {
        let git = try await GitRunner.resolve(repository: configuration.repository)
        let agent = try await AgentRunner.resolve(
            model: configuration.model, maxTurns: configuration.maxTurns)
        let worktree = try await checkout(request, git: git)

        var outcome: AgentEvent.Result?
        do {
            outcome = try await turn(
                agent, prompt: prompt(question, for: request), in: worktree,
                resuming: request.sessionID)
        } catch where AgentRunner.isMissingSession(error) {
            // The branch is checked out either way, so the answer survives losing the session.
            outcome = try await turn(
                agent, prompt: prompt(question, for: request), in: worktree, resuming: nil)
        }
        guard let outcome else {
            throw SubprocessRunner.Failure(reason: "The agent exited without answering.")
        }
        return outcome
    }

    private func turn(
        _ agent: AgentRunner, prompt: String, in worktree: URL, resuming session: String?
    ) async throws -> AgentEvent.Result {
        var outcome: AgentEvent.Result?
        for try await event in agent.run(
            prompt: prompt, in: worktree, resuming: session, mode: .question)
        {
            report(event)
            if case .finished(let result) = event { outcome = result }
        }
        try Task.checkCancellation()
        return outcome ?? AgentEvent.Result(isError: true, summary: "No answer came back.")
    }

    /// Reused across the conversation, and refreshed from the remote when it is first cut.
    private func checkout(_ request: FeatureRequest, git: GitRunner) async throws -> URL {
        let worktree = Self.worktreeURL(for: request)
        if FileManager.default.fileExists(atPath: worktree.appending(path: ".git").path) {
            return worktree
        }
        try FileManager.default.createDirectory(
            at: worktree.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: worktree)
        await git.fetch()
        try await git.readOnlyWorktree(at: worktree, branch: request.branch)
        return worktree
    }

    private func prompt(_ question: String, for request: FeatureRequest) -> String {
        FeatureRequestPrompt.question(request, question: question)
    }

    static func worktreeURL(for request: FeatureRequest) -> URL {
        AppPaths.applicationSupport()
            .appending(path: "feature-request-questions")
            .appending(path: request.shortID)
    }

    /// Torn down when the conversation closes; the transcript is what is worth keeping.
    static func discardWorktree(for request: FeatureRequest, repository: URL) async {
        guard let git = try? await GitRunner.resolve(repository: repository) else { return }
        await git.discardWorktree(at: worktreeURL(for: request))
    }
}
