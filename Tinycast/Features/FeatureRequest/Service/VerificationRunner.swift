import Foundation

/// Runs `AGENTS.md`'s definition of done against a worktree. Its verdict is what opens a PR.
///
/// The agent is told to run these too, and usually does — this run is the one that counts, because
/// an agent reporting on its own work is exactly the claim a gate exists to check.
struct VerificationRunner: Sendable {
    let worktree: URL
    let environment: [String: String]
    let derivedData: URL
    let xcodebuild: URL?

    static func resolve(worktree: URL, derivedData: URL) async -> VerificationRunner {
        // `lint.sh` shells out to node, which a version manager keeps off every shared `bin`.
        let node = await ExecutableLocator.locate("node")
        let xcodebuild = await ExecutableLocator.locate("xcodebuild")
        let extraPaths = [node, xcodebuild].compactMap { $0?.deletingLastPathComponent().path }
        return VerificationRunner(
            worktree: worktree, environment: SubprocessRunner.environment(prepending: extraPaths),
            derivedData: derivedData, xcodebuild: xcodebuild)
    }

    /// Stops at the first failure: the agent can only usefully be told about one gate at a time.
    func run(
        changes: [WorktreeChange], numstat: String,
        onStep: @Sendable @escaping (VerificationReport.Step) -> Void
    ) async throws -> VerificationReport {
        var report = VerificationReport()
        for step in VerificationReport.Step.allCases {
            try Task.checkCancellation()
            onStep(step)
            let outcome = try await evaluate(step, changes: changes, numstat: numstat)
            report.outcomes.append(outcome)
            if outcome.state == .failed { break }
        }
        return report
    }

    private func evaluate(
        _ step: VerificationReport.Step, changes: [WorktreeChange], numstat: String
    ) async throws -> VerificationReport.Outcome {
        switch step {
        case .modelPurity: return try await modelPurity()
        case .projectSync: return projectSync(changes: changes)
        case .testIntegrity: return testIntegrity(changes: changes, numstat: numstat)
        case .lint: return try await script("Scripts/lint.sh", step: .lint, timeout: .seconds(600))
        case .tests:
            return try await script("Scripts/run-tests.sh", step: .tests, timeout: .seconds(1800))
        case .build: return try await build()
        }
    }

    /// A `Model/` file reaching for AppKit is the invariant the harnesses cannot catch themselves.
    private func modelPurity() async throws -> VerificationReport.Outcome {
        let pattern = "import AppKit\\|import SwiftUI\\|import Cocoa"
        let result = try await bash(
            "grep -rln '\(pattern)' Tinycast/Features/*/Model/ || true", timeout: .seconds(120))
        let hits = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hits.isEmpty else { return .init(step: .modelPurity, state: .passed, digest: "") }
        return .init(
            step: .modelPurity, state: .failed,
            digest: "These files under Features/*/Model/ import a UI framework:\n" + hits)
    }

    private func projectSync(changes: [WorktreeChange]) -> VerificationReport.Outcome {
        let sources = ProjectSync.compilableSources(in: changes)
        guard !sources.isEmpty else { return .init(step: .projectSync, state: .passed, digest: "") }
        let project = worktree.appending(path: "Tinycast.xcodeproj/project.pbxproj")
        guard let contents = try? String(contentsOf: project, encoding: .utf8) else {
            return .init(
                step: .projectSync, state: .skipped, digest: "the project file could not be read")
        }
        let missing = ProjectSync.unreferenced(sources: sources, inProject: contents)
        guard !missing.isEmpty else { return .init(step: .projectSync, state: .passed, digest: "") }
        return .init(
            step: .projectSync, state: .failed, digest: ProjectSync.digest(unreferenced: missing))
    }

    /// Pure, from the diff the run already read: the suite may not shrink to make a gate pass.
    private func testIntegrity(changes: [WorktreeChange], numstat: String)
        -> VerificationReport.Outcome
    {
        let found = TestIntegrity.regressions(
            changes: changes, deltas: TestIntegrity.parse(numstat: numstat))
        guard !found.isEmpty else { return .init(step: .testIntegrity, state: .passed, digest: "") }
        return .init(
            step: .testIntegrity, state: .failed, digest: TestIntegrity.digest(regressions: found))
    }

    /// Exit 2 is `lint.sh`'s own "tool not installed", which is unverifiable rather than failing.
    private func script(_ path: String, step: VerificationReport.Step, timeout: Duration)
        async throws -> VerificationReport.Outcome
    {
        // Passed as an argument rather than interpolated: the path is not ours to quote.
        let result = try await SubprocessRunner.run(
            URL(fileURLWithPath: "/bin/bash"), [worktree.appending(path: path).path],
            in: worktree, environment: environment, timeout: timeout)
        if result.status == 2, step == .lint {
            return .init(step: step, state: .skipped, digest: "swiftlint is not installed")
        }
        guard result.succeeded else {
            return .init(
                step: step, state: .failed,
                digest: VerificationReport.digest(for: step, output: result.output))
        }
        return .init(step: step, state: .passed, digest: "")
    }

    /// Debug per `AGENTS.md`, into a private derived-data dir, and named as its own channel so the
    /// artifact this gate produces is the one `Try It` can launch beside a running Tinycast.
    private func build() async throws -> VerificationReport.Outcome {
        guard let xcodebuild else {
            return .init(step: .build, state: .skipped, digest: "xcodebuild is not installed")
        }
        let result = try await SubprocessRunner.run(
            xcodebuild,
            [
                "-project", "Tinycast.xcodeproj", "-scheme", "Tinycast",
                "-configuration", "Debug", "-derivedDataPath", derivedData.path,
                "CODE_SIGNING_ALLOWED=NO"
            ] + PreviewBuild.buildSettings + ["build"],
            in: worktree, environment: environment, timeout: .seconds(2400))
        guard result.succeeded else {
            return .init(
                step: .build, state: .failed,
                digest: VerificationReport.digest(for: .build, output: result.output))
        }
        return .init(step: .build, state: .passed, digest: "")
    }

    private func bash(_ command: String, timeout: Duration) async throws -> SubprocessRunner.Result {
        try await SubprocessRunner.run(
            URL(fileURLWithPath: "/bin/bash"), ["-c", command], in: worktree,
            environment: environment, timeout: timeout)
    }
}
