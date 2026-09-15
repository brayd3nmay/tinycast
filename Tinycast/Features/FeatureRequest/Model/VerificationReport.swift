import Foundation

/// The gates `AGENTS.md` calls the definition of done, and how the change fared against them.
struct VerificationReport: Codable, Sendable, Equatable {
    /// Cheapest first: a grep answers instantly, so nothing waits on a build to learn it failed.
    enum Step: String, Codable, Sendable, CaseIterable {
        case modelPurity
        case projectSync
        case testIntegrity
        case lint
        case tests
        case build

        var title: String {
            switch self {
            case .modelPurity: return "Model purity"
            case .projectSync: return "Project sync"
            case .testIntegrity: return "Test integrity"
            case .lint: return "Lint"
            case .tests: return "Tests"
            case .build: return "Build"
            }
        }
    }

    struct Outcome: Codable, Sendable, Equatable, Identifiable {
        enum State: String, Codable, Sendable {
            case passed
            case failed
            /// The gate's tool is not installed. Reported, never silently treated as a pass.
            case skipped
        }

        let step: Step
        let state: State
        /// The failing lines only; a full xcodebuild log would dwarf everything else on disk.
        let digest: String

        var id: Step { step }
        var mark: String {
            switch state {
            case .passed: return "✓"
            case .failed: return "✗"
            case .skipped: return "⊘"
            }
        }
    }

    var outcomes: [Outcome]

    init(outcomes: [Outcome] = []) {
        self.outcomes = outcomes
    }

    /// Every gate reached a verdict and none failed; a skipped gate is reported, not counted against.
    var passed: Bool {
        outcomes.count == Step.allCases.count && !outcomes.contains { $0.state == .failed }
    }

    var failure: Outcome? { outcomes.first { $0.state == .failed } }

    var skipped: [Outcome] { outcomes.filter { $0.state == .skipped } }

    /// What a retry is told went wrong; empty when nothing did.
    var digest: String {
        guard let failure else { return "" }
        return "\(failure.step.title) failed:\n\(failure.digest)"
    }

    /// One line per gate for the pull request body and the detail pane.
    var summaryLines: [String] {
        outcomes.map { outcome in
            let suffix = outcome.state == .skipped ? " — \(outcome.digest)" : ""
            return "\(outcome.mark) \(outcome.step.title)\(suffix)"
        }
    }

    /// Keeps the lines a human would look at first, which is never the middle of a build log.
    static func digest(for step: Step, output: String, limit: Int = 40) -> String {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        let salient = lines.filter { isSalient($0, for: step) }
        let kept = salient.isEmpty ? Array(lines.suffix(limit)) : Array(salient.prefix(limit))
        let text = kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "(no output)" : text
    }

    private static func isSalient(_ line: String, for step: Step) -> Bool {
        switch step {
        case .build: return line.contains("error:")
        case .tests: return line.contains("FAIL") || line.contains("assertion")
        case .lint: return line.contains("error:") || line.contains("✗")
        // These print one offending path per line, so every line they print is the finding.
        case .modelPurity, .projectSync, .testIntegrity:
            return !line.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
}
