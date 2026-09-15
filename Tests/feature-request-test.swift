// Branch naming, the agent's event stream, the verification gates, and the request log.
import Foundation

@main
@MainActor
struct FeatureRequestTests {
    static var failures = 0
    static var passes = 0

    static func main() {
        slugs()
        branchNames()
        titles()
        pullRequestBodies()
        toolSummaries()
        streamDecoding()
        partialLines()
        resultSubtypes()
        digests()
        reportVerdicts()
        porcelainParsing()
        projectSync()
        testIntegrity()
        previewRetention()
        transcriptSegments()
        questionPrompts()
        prompts()
        followUpPrompts()
        legacyRecordsDecode()
        pullRequestURLs()
        storeSettlesInterruptedRuns()
        storeTrimsFinishedOnly()

        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Naming

    static func slugs() {
        expect(FeatureBranch.slug("Add a dark mode toggle") == "add-a-dark-mode-toggle", "words")
        expect(FeatureBranch.slug("  Fix   the   spacing  ") == "fix-the-spacing", "runs collapse")
        expect(FeatureBranch.slug("Café ölquantität") == "cafe-olquantitat", "diacritics fold")
        expect(FeatureBranch.slug("!!!") == "", "punctuation alone yields nothing")
        expect(FeatureBranch.slug("日本語") == "", "non-ASCII scripts yield nothing")
        expect(!FeatureBranch.slug(String(repeating: "word ", count: 40)).hasSuffix("-"), "no tail")
        expect(FeatureBranch.slug(String(repeating: "a", count: 90)).count <= 48, "capped")
    }

    static func branchNames() {
        let id = UUID(uuidString: "ABCDEF01-2345-6789-ABCD-EF0123456789")!
        let name = FeatureBranch.name(prompt: "Add a dark mode toggle", id: id)
        expect(name == "feature/add-a-dark-mode-toggle-abcdef", "branch carries slug and id")
        let unnamed = FeatureBranch.name(prompt: "!!!", id: id)
        expect(unnamed == "feature/request-abcdef", "an unsluggable prompt still names a branch")
        // Two identically worded requests must never land on the same branch.
        let other = UUID(uuidString: "11111111-2345-6789-ABCD-EF0123456789")!
        expect(
            FeatureBranch.name(prompt: "Add a toggle", id: id)
                != FeatureBranch.name(prompt: "Add a toggle", id: other), "ids disambiguate")
    }

    static func titles() {
        expect(FeatureBranch.title(prompt: "Add a toggle") == "Add a toggle", "short titles pass")
        expect(FeatureBranch.title(prompt: "") == "Implement requested feature", "empty falls back")
        expect(
            FeatureBranch.title(prompt: "First line\nSecond line") == "First line",
            "only the first line")
        let long = FeatureBranch.title(prompt: String(repeating: "alpha ", count: 40))
        expect(long.count <= 73 && long.hasSuffix("…"), "long titles clip on a word boundary")
        expect(!long.contains("alph…"), "the clip never lands mid-word")
    }

    static func pullRequestBodies() {
        var request = FeatureRequest(prompt: "Add a toggle", branch: "feature/x")
        request.attempts = [.init(id: 1), .init(id: 2)]
        let report = VerificationReport(outcomes: [
            .init(step: .lint, state: .skipped, digest: "swiftlint is not installed"),
            .init(step: .tests, state: .passed, digest: "")
        ])
        let body = FeatureBranch.body(request: request, report: report)
        expect(body.contains("Add a toggle"), "body quotes the request")
        expect(body.contains("⊘ Lint — swiftlint is not installed"), "a skipped gate is disclosed")
        expect(body.contains("✓ Tests"), "a passed gate is listed")
        expect(body.contains("Took 2 attempts"), "retries are disclosed")
        let once = FeatureBranch.body(
            request: FeatureRequest(prompt: "x", branch: "b"), report: nil)
        expect(!once.contains("attempts"), "a single attempt says nothing about attempts")
    }

    // MARK: - The agent stream

    static func toolSummaries() {
        expect(
            AgentEvent.summary(tool: "Edit", input: ["file_path": "/a/b/Tinycast/Foo.swift"])
                == "Edit Tinycast/Foo.swift", "paths shorten to two components")
        expect(
            AgentEvent.summary(tool: "Bash", input: ["command": "ls", "description": "List files"])
                == "Bash List files", "a description beats the raw command")
        expect(
            AgentEvent.summary(tool: "Bash", input: ["command": "ls -la"]) == "Bash ls -la",
            "the command stands in when there is no description")
        expect(AgentEvent.summary(tool: "Mystery", input: [:]) == "Mystery", "unknown tools name")
        expect(
            AgentEvent.summary(tool: "Bash", input: ["command": "a\nb"]) == "Bash a b",
            "newlines never reach a one-line row")
        let long = AgentEvent.summary(
            tool: "Grep", input: ["pattern": String(repeating: "x", count: 200)])
        expect(long.count <= 78, "a long argument is clipped")
    }

    static func streamDecoding() {
        let system = #"{"type":"system","subtype":"init","session_id":"s-1","model":"opus"}"#
        expect(AgentEventDecoder.events(from: system) == [.started(sessionID: "s-1")], "init")
        let assistant = """
            {"type":"assistant","message":{"content":[\
            {"type":"text","text":"Looking at the palette.\\nMore detail."},\
            {"type":"tool_use","name":"Read","input":{"file_path":"/x/Palette/Root.swift"}}]}}
            """
        expect(
            AgentEventDecoder.events(from: assistant)
                == [.narration("Looking at the palette."), .activity("Read Palette/Root.swift")],
            "text and tool blocks both surface, in order")
        expect(AgentEventDecoder.events(from: "not json").isEmpty, "CLI chatter is ignored")
        expect(AgentEventDecoder.events(from: "").isEmpty, "blank lines are ignored")
        expect(
            AgentEventDecoder.events(from: #"{"type":"user","message":{}}"#).isEmpty,
            "tool results are not progress")
    }

    static func partialLines() {
        var decoder = AgentEventDecoder()
        let line = #"{"type":"system","subtype":"init","session_id":"s-2"}"# + "\n"
        let bytes = Array(line.utf8)
        let head = Data(bytes[..<20])
        let tail = Data(bytes[20...])
        expect(decoder.push(head).isEmpty, "half a line yields nothing yet")
        expect(decoder.push(tail) == [.started(sessionID: "s-2")], "the rest completes it")
        // The final line arrives without its newline when the process exits.
        var trailing = AgentEventDecoder()
        _ = trailing.push(Data(#"{"type":"system","subtype":"init","session_id":"s-3"}"#.utf8))
        expect(trailing.finish() == [.started(sessionID: "s-3")], "the tail is flushed by hand")
        expect(trailing.finish().isEmpty, "flushing twice yields nothing")
    }

    static func resultSubtypes() {
        let success =
            #"{"type":"result","subtype":"success","is_error":false,"result":"Done.","num_turns":7,"session_id":"s"}"#
        guard case .finished(let done)? = AgentEventDecoder.events(from: success).first else {
            return fail("a success result decodes")
        }
        expect(!done.isError && done.summary == "Done." && done.turns == 7, "result fields carry")
        expect(done.sessionID == "s", "the session is carried for the retry to resume")

        let capped = #"{"type":"result","subtype":"error_max_turns","is_error":true,"result":""}"#
        guard case .finished(let hit)? = AgentEventDecoder.events(from: capped).first else {
            return fail("a turn-limit result decodes")
        }
        expect(hit.isError, "a turn limit is an error")
        expect(hit.summary.contains("turn limit"), "an empty result still explains itself")
    }

    // MARK: - Verification

    static func digests() {
        let build = """
            Compiling Foo.swift
            /x/Foo.swift:3:1: error: cannot find 'bar' in scope
            note: something
            """
        expect(
            VerificationReport.digest(for: .build, output: build)
                == "/x/Foo.swift:3:1: error: cannot find 'bar' in scope",
            "a build digest keeps the errors and nothing else")
        let tests = "ok    calc-test\nFAIL  emoji-test  assertion failed after 1s"
        expect(
            VerificationReport.digest(for: .tests, output: tests).contains("FAIL  emoji-test"),
            "a test digest keeps the failures")
        expect(
            !VerificationReport.digest(for: .tests, output: tests).contains("ok    calc-test"),
            "a test digest drops the passes")
        expect(
            VerificationReport.digest(for: .build, output: "") == "(no output)",
            "no output still reads as something")
        // Nothing salient: the tail is the only place left for the reason.
        let quiet = (1...80).map { "line \($0)" }.joined(separator: "\n")
        let digest = VerificationReport.digest(for: .build, output: quiet)
        expect(digest.contains("line 80") && !digest.contains("line 1\n"), "falls back to the tail")
    }

    static func reportVerdicts() {
        let every = VerificationReport.Step.allCases.map {
            VerificationReport.Outcome(step: $0, state: .passed, digest: "")
        }
        expect(VerificationReport(outcomes: every).passed, "every gate green is a pass")
        expect(!VerificationReport(outcomes: Array(every.dropLast())).passed, "a short run is not")
        expect(!VerificationReport().passed, "an empty report is never a pass")

        var mixed = every
        mixed[2] = .init(step: mixed[2].step, state: .skipped, digest: "not installed")
        expect(VerificationReport(outcomes: mixed).passed, "a skipped gate does not block")
        mixed[1] = .init(step: mixed[1].step, state: .failed, digest: "boom")
        let failed = VerificationReport(outcomes: mixed)
        expect(!failed.passed, "a failed gate blocks")
        expect(failed.failure?.digest == "boom", "the first failure is the one reported")
        expect(failed.digest.contains("boom"), "the retry digest quotes it")
        expect(VerificationReport(outcomes: every).digest.isEmpty, "a pass has no digest")
    }

    // MARK: - The worktree

    static func porcelainParsing() {
        let changes = WorktreeChange.parse(
            porcelain: """
                 M Tinycast/App/AppCore.swift
                ?? Tinycast/Features/New/Model/Thing.swift
                A  Tests/thing-test.swift
                R  Old/Name.swift -> New/Name.swift
                """)
        expect(changes.count == 4, "every line is a change")
        expect(!changes[0].isDeleted, "a modification is not a deletion")
        expect(changes[0].path == "Tinycast/App/AppCore.swift" && !changes[0].isAdded, "modified")
        expect(changes[1].isAdded, "untracked counts as added")
        expect(changes[2].isAdded, "staged-add counts as added")
        expect(changes[3].path == "New/Name.swift", "a rename reports its destination")
        expect(WorktreeChange.parse(porcelain: "").isEmpty, "a clean tree has no changes")
        let quoted = WorktreeChange.parse(porcelain: #"?? "Tinycast/a b.swift""#)
        expect(quoted.first?.path == "Tinycast/a b.swift", "git's quoting is unwrapped")
    }

    static func projectSync() {
        let changes = [
            WorktreeChange(
                path: "Tinycast/Features/New/Model/Thing.swift", isAdded: true, isDeleted: false),
            WorktreeChange(path: "Tinycast/App/AppCore.swift", isAdded: false, isDeleted: false),
            WorktreeChange(path: "Tests/thing-test.swift", isAdded: true, isDeleted: false),
            WorktreeChange(path: "docs/features/thing.md", isAdded: true, isDeleted: false)
        ]
        let sources = ProjectSync.compilableSources(in: changes)
        expect(sources == ["Tinycast/Features/New/Model/Thing.swift"], "only added app sources")

        let project = "… path = Other.swift; … /* Thing.swift */ …"
        expect(
            ProjectSync.unreferenced(sources: sources, inProject: project).isEmpty,
            "a referenced file is in sync")
        expect(
            ProjectSync.unreferenced(sources: sources, inProject: "nothing here") == sources,
            "an unreferenced file is caught")
        expect(
            ProjectSync.digest(unreferenced: sources).contains("xcodegen generate"),
            "the digest names the command that fixes it")
    }

    static func testIntegrity() {
        expect(TestIntegrity.isGuarded("Tests/calc-test.swift"), "a harness is guarded")
        expect(TestIntegrity.isGuarded("Scripts/run-tests.sh"), "so is the script that runs them")
        expect(!TestIntegrity.isGuarded("Tinycast/App/AppCore.swift"), "shipped code is not")
        expect(!TestIntegrity.isGuarded("Tests/fixtures/a.json"), "only Swift harnesses are")

        // `git diff --numstat -M`, including both spellings of a rename.
        let deltas = TestIntegrity.parse(
            numstat: """
                0\t2\tTests/gone.swift
                4\t1\tTests/grown.swift
                0\t2\tTests/{keep.swift => renamed.swift}
                1\t9\tScripts/run-tests.sh
                -\t-\tdocs/logo.png
                """)
        expect(deltas.count == 4, "a binary file has no lines to lose")
        expect(deltas[2].path == "Tests/renamed.swift", "a brace rename resolves to its destination")
        expect(!deltas[1].shrank, "a test that grew did not shrink")
        expect(deltas[3].shrank, "the dispatcher losing run lines is a shrink")
        expect(
            TestIntegrity.parse(numstat: "3\t1\told/a.swift => new/b.swift").first?.path
                == "new/b.swift", "a bare rename resolves too")

        let deleted = [
            WorktreeChange(path: "Tests/emoji-test.swift", isAdded: false, isDeleted: true),
            WorktreeChange(path: "Tinycast/App/Gone.swift", isAdded: false, isDeleted: true)
        ]
        let found = TestIntegrity.regressions(changes: deleted, deltas: deltas)
        expect(found.contains { $0.contains("Tests/emoji-test.swift was deleted") }, "deletion")
        expect(
            !found.contains { $0.contains("Tinycast/App/Gone.swift") },
            "deleting shipped code is the change, not a regression")
        expect(found.contains { $0.contains("Tests/gone.swift lost 2 lines") }, "a shrink counts")
        expect(
            found.contains { $0.contains("Scripts/run-tests.sh lost 8 lines") },
            "a dropped run line is caught")
        expect(!found.contains { $0.contains("grown") }, "a test that grew is fine")
        let one = TestIntegrity.regressions(
            changes: [], deltas: TestIntegrity.parse(numstat: "0\t1\tTests/a.swift"))
        expect(one.first?.contains("lost 1 line (") == true, "one line is not '1 lines'")

        // A file counted as deleted must not also be reported as having shrunk to nothing.
        let both = TestIntegrity.regressions(
            changes: [WorktreeChange(path: "Tests/gone.swift", isAdded: false, isDeleted: true)],
            deltas: deltas)
        expect(both.filter { $0.contains("Tests/gone.swift") }.count == 1, "reported once")

        expect(
            TestIntegrity.regressions(changes: [], deltas: []).isEmpty,
            "a run that touches no tests is clean")
        expect(
            TestIntegrity.digest(regressions: found).contains("Restore what you removed"),
            "the digest says what to do about it")
    }

    static func previewRetention() {
        // Newest-first, the same order the log itself is in.
        let live = ["aaa", "bbb", "ccc", "ddd", "eee"]
        let disk = ["aaa", "bbb", "ccc", "ddd", "eee"]
        expect(
            PreviewRetention.expired(onDisk: disk, live: live, limit: 3).sorted() == ["ddd", "eee"],
            "only the newest three survive")
        expect(
            PreviewRetention.expired(onDisk: ["zzz"], live: live, limit: 3) == ["zzz"],
            "a preview whose request is gone is an orphan")
        expect(
            PreviewRetention.expired(onDisk: [], live: live, limit: 3).isEmpty,
            "nothing on disk is nothing to sweep")
        expect(
            PreviewRetention.expired(onDisk: disk, live: [], limit: 3).sorted() == disk.sorted(),
            "an emptied log sweeps every preview")
        // A running preview is skipped rather than deleted out from under itself.
        expect(
            !PreviewRetention.expired(onDisk: disk, live: live, limit: 3, running: "eee")
                .contains("eee"), "the running preview is spared")
        expect(
            PreviewRetention.expired(onDisk: disk, live: live, limit: 3, running: "eee")
                .contains("ddd"), "sparing one does not spare the rest")
        // A live request with no preview on disk must not consume one of the three slots.
        expect(
            !PreviewRetention.expired(
                onDisk: ["ccc", "ddd"], live: ["aaa", "bbb", "ccc", "ddd"], limit: 3
            ).contains("ddd"), "absent previews do not take a slot")
    }

    static func transcriptSegments() {
        // No tool calls: the reply is one run of text.
        let plain = AgentMessage(role: .agent, text: "All done.")
        expect(plain.segments == [.text("All done.")], "plain text is one segment")

        // Calls are pinned where they happened, so text splits around them in order.
        let read = AgentToolCall(id: UUID(), label: "Read Palette/Root.swift", textOffset: 6)
        let grep = AgentToolCall(id: UUID(), label: "Grep cellSize", textOffset: 12)
        let mixed = AgentMessage(
            role: .agent, text: "Let me look at that", toolCalls: [grep, read])
        let kinds = mixed.segments.map { segment -> String in
            switch segment {
            case .text(let text): return "text(\(text))"
            case .tool(let call): return "tool(\(call.label))"
            }
        }
        expect(
            kinds == [
                "text(Let me)", "tool(Read Palette/Root.swift)", "text( look )",
                "tool(Grep cellSize)", "text(at that)"
            ], "segments interleave in offset order regardless of array order")

        // An offset past the end must not slice off the end of the string.
        let overrun = AgentMessage(
            role: .agent, text: "hi", toolCalls: [AgentToolCall(label: "Read x", textOffset: 99)])
        expect(overrun.segments.count == 2, "an overrunning offset still yields text then tool")
        expect(AgentMessage(role: .agent, text: "").segments.isEmpty, "empty text has no segments")
    }

    static func questionPrompts() {
        let request = FeatureRequest(prompt: "Add a store", branch: "feature/store")
        let prompt = FeatureRequestPrompt.question(request, question: "where does the grid live?")
        expect(prompt.contains("where does the grid live?"), "the question is quoted")
        expect(prompt.contains("Add a store"), "the original request is context")
        expect(prompt.contains("do not edit"), "the turn is told it may not write")
        expect(
            !prompt.contains("run-tests.sh"),
            "a question runs no gates, so it is not told about them")
    }

    // MARK: - Prompts

    static func prompts() {
        let request = FeatureRequest(prompt: "Add a toggle", branch: "feature/x")
        let initial = FeatureRequestPrompt.initial(request)
        expect(initial.contains("Add a toggle"), "the request is quoted verbatim")
        expect(initial.contains("AGENTS.md"), "the agent is pointed at the project's standard")
        expect(initial.contains("run-tests.sh"), "the gates are stated")
        expect(initial.contains("Do not commit"), "committing is left to the runner")

        let report = VerificationReport(outcomes: [
            .init(step: .tests, state: .failed, digest: "FAIL  emoji-test")
        ])
        let retry = FeatureRequestPrompt.retry(request, report: report, attempt: 2, of: 3)
        expect(retry.contains("FAIL  emoji-test"), "the retry is told what actually failed")
        expect(retry.contains("attempt 2 of 3"), "the retry knows how much rope is left")
        expect(retry.contains("Add a toggle"), "the retry still carries the original request")
        expect(retry.contains("do not weaken"), "the retry may not delete the failing test")
    }

    static func followUpPrompts() {
        var request = FeatureRequest(prompt: "Add a toggle", branch: "feature/x")
        expect(!request.acceptsFollowUp, "a request with no branch pushed cannot be amended")
        request.status = .opened(url: URL(string: "https://example.com/pull/1")!)
        expect(request.acceptsFollowUp, "one with a pull request can")
        request.status = .pushed
        expect(request.acceptsFollowUp, "so can one that only pushed a branch")

        let prompt = FeatureRequestPrompt.followUp(request, change: "Make the icons bigger")
        expect(prompt.contains("Make the icons bigger"), "the change is quoted")
        expect(prompt.contains("Add a toggle"), "so is the request it amends")
        expect(
            prompt.contains("Do not rebuild the feature from scratch"),
            "the agent is told to build on what is there")
        expect(prompt.contains("run-tests.sh"), "the gates still apply to a change")
        expect(
            prompt.contains("Do not commit"), "publishing stays with the runner for a change too")
    }

    /// A log written before follow-ups existed has neither field; decoding must not throw.
    static func legacyRecordsDecode() {
        let legacy = """
            [{"id":"46A9F556-7A1B-4B4F-A12E-F200A19BB652","prompt":"old","branch":"feature/old",\
            "createdAt":768000000,"status":{"pushed":{}},"attempts":[]}]
            """
        guard
            let decoded = try? JSONDecoder().decode(
                [FeatureRequest].self, from: Data(legacy.utf8))
        else {
            return fail("a record without sessionID or followUps still decodes")
        }
        expect(decoded.first?.sessionID == nil, "the missing session defaults to none")
        expect(decoded.first?.followUps.isEmpty == true, "the missing follow-ups default to empty")
        expect(decoded.first?.acceptsFollowUp == true, "and it can still be amended")
    }

    static func pullRequestURLs() {
        let output = """
            Warning: 1 uncommitted change
            https://github.com/owner/repo/pull/42
            """
        expect(
            GitRunner.pullRequestURL(in: output)?.absoluteString
                == "https://github.com/owner/repo/pull/42", "the URL is found among the chatter")
        expect(GitRunner.pullRequestURL(in: "no url here") == nil, "no URL is not a URL")
        expect(
            GitRunner.pullRequestURL(in: "https://github.com/owner/repo") == nil,
            "a repo URL is not a pull request")
    }

    // MARK: - The log

    static func storeSettlesInterruptedRuns() {
        let defaults = suite("settle")
        let live = FeatureRequest(
            prompt: "a", branch: "b", status: .implementing(attempt: 1))
        let done = FeatureRequest(prompt: "c", branch: "d", status: .pushed)
        guard let seeded = try? JSONEncoder().encode([live, done]) else {
            return fail("the seed encodes")
        }
        defaults.set(seeded, forKey: "featureRequests")

        let store = FeatureRequestStore(defaults: defaults)
        guard case .failed(let reason)? = store.request(id: live.id)?.status else {
            return fail("a run that outlived its process is settled")
        }
        expect(reason.contains("Interrupted"), "and says why")
        expect(store.request(id: done.id)?.status == .pushed, "a finished run is left alone")
        expect(store.active == nil, "nothing is left running after a relaunch")
    }

    static func storeTrimsFinishedOnly() {
        let defaults = suite("trim")
        let store = FeatureRequestStore(defaults: defaults)
        for index in 0..<45 {
            store.add(
                FeatureRequest(
                    prompt: "request \(index)", branch: "b\(index)",
                    status: index < 3 ? .queued : .pushed))
        }
        expect(store.requests.count == 40, "the log is capped")
        expect(store.queued.count == 3, "a queued request never falls off the end")
        expect(store.requests.first?.prompt == "request 44", "newest first")

        let queued = store.queued
        store.clearFinished()
        expect(store.requests.map(\.id) == queued.map(\.id), "clearing keeps what is still to run")
    }

    // MARK: - Helpers

    /// A private suite per case: `.standard` would carry state between runs and between tests.
    static func suite(_ name: String) -> UserDefaults {
        let suite = "com.tinycast.tests.feature-request.\(name)"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            passes += 1
        } else {
            fail(label)
        }
    }

    static func fail(_ label: String) {
        print("FAIL: \(label)")
        failures += 1
    }
}
