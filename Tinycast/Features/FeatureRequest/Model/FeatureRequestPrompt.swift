import Foundation

/// What the agent is told, on the first attempt and on each retry. Pure text, so it is testable.
enum FeatureRequestPrompt {
    /// Assembled, never written out: the literal would trip the very grep this line describes.
    private static let purityPattern =
        ["AppKit", "SwiftUI", "Cocoa"].map { "import " + $0 }.joined(separator: "\\|")

    /// Restated here rather than linked: the agent is judged on exactly these five gates.
    static var gates: String {
        """
        1. No file under `Tinycast/Features/*/Model/` imports a UI framework:
           `grep -rln '\(purityPattern)' Tinycast/Features/*/Model/` prints nothing.
        2. Every source file you added is in `Tinycast.xcodeproj` — run `xcodegen generate`.
        3. No file under `Tests/` is deleted or made shorter, and no `run` line is removed
           from `Scripts/run-tests.sh`.
        4. `./Scripts/lint.sh` is clean.
        5. `./Scripts/run-tests.sh` passes.
        6. `xcodebuild -scheme Tinycast -configuration Debug build` succeeds.
        """
    }

    static func initial(_ request: FeatureRequest) -> String {
        """
        Implement a feature in this repository, which is the Tinycast macOS app.

        ## The request

        \(request.prompt)

        ## How to work

        Read `AGENTS.md` before writing any Swift; it is the project's own standard and it is \
        binding. Follow the folder layout, the naming table, the comment rules and the \
        non-negotiables it lists. Match the surrounding code rather than introducing a new style.

        If the request is ambiguous, take the most conservative reading that still delivers it, \
        and say which reading you took in your final message. If the request cannot be built \
        without a decision only the user can make, stop and explain why instead of guessing.

        Regenerate whatever your change invalidates: `xcodegen generate` after editing \
        `project.yml`, and the matching `Scripts/gen-*.js` after editing generated data. Add a \
        harness under `Tests/` and register it in `Scripts/run-tests.sh` for any pure logic you \
        introduce. Update the docs your change makes wrong.

        ## Done means

        \(gates)

        Run them yourself and fix what they report. They will be run again after you stop, and the \
        pull request only opens if all four pass.

        ## Leave alone

        Do not commit, push, create a branch or open a pull request — that is handled for you once \
        the gates pass. Leave your work uncommitted in the working tree. Do not write planning \
        notes, scratch files or summary documents; the only files you leave behind are the ones \
        the feature needs.

        Finish with a short plain-text summary of what you changed and why.
        """
    }

    /// A question about the branch. It can read the files; it is told plainly it may not touch them.
    static func question(_ request: FeatureRequest, question: String) -> String {
        """
        Answer a question about this branch, which holds a feature you built. The working tree is \
        checked out here and you can read it.

        ## The question

        \(question)

        ## How to answer

        Answer it and stop. You are read-only for this turn: do not edit, create or delete \
        anything, and do not run commands. Read the files if you need to rather than answering \
        from memory — the branch is what is true, not your recollection of writing it.

        Be direct and short. Name files as repo-relative paths so they can be found. If the answer \
        is a change the user would have to make, describe it — do not make it, and do not offer to.

        For reference, the request this branch was built from:

        \(request.prompt)
        """
    }

    /// A change asked for after the build was tried. The branch already holds the work it edits.
    static func followUp(_ request: FeatureRequest, change: String) -> String {
        """
        You already built this feature, and it is checked out in this worktree on its own branch. \
        The user has run it and wants a change.

        ## The change

        \(change)

        ## What to do

        Make that change on top of the work that is already here. Do not rebuild the feature from \
        scratch, and do not undo parts of it the user did not ask you to change. If the change \
        conflicts with the original request, follow the change — it is the more recent instruction \
        — and say so in your final message.

        ## Done means

        \(gates)

        ## Leave alone

        Do not commit, push or touch the pull request; that is handled for you. Leave your work \
        uncommitted in the working tree.

        For reference, the request this branch was built from:

        \(request.prompt)
        """
    }

    /// The failing gate verbatim: a retry that is told only "tests failed" re-runs the same guess.
    static func retry(_ request: FeatureRequest, report: VerificationReport, attempt: Int, of limit: Int)
        -> String
    {
        """
        The change you just made does not pass verification. This is attempt \(attempt) of \(limit).

        ## What failed

        \(report.digest)

        ## What to do

        Fix the cause, in the work you already have — do not revert it and start over, and do not \
        weaken, skip or delete a test to make the gate pass. If the failure is in code you did not \
        touch, say so in your final message rather than papering over it.

        Then re-run the gate that failed, and the ones after it:

        \(gates)

        The original request, unchanged:

        \(request.prompt)
        """
    }
}
