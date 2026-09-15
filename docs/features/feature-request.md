# Request a Feature

Describe a feature in the palette and Tinycast hands it to a local coding agent, which implements it in
a throwaway git worktree. The project's own definition of done is then run against the result, and a
pull request opens only once every gate is green. A failing gate goes back to the same agent session as
a correction, up to the retry limit.

The agent is the `claude` CLI already on the machine — the same install `Settings › AI` discovers — run
with every tool enabled. That is the opposite of the chat route in [ai.md](ai.md), and the difference is
deliberate: see [Two ways to run the same CLI](#two-ways-to-run-the-same-cli).

## Invariants

- **The agent never touches the user's checkout.** Every run happens in a `git worktree` cut from
  `origin/<base>`, under Application Support. The checkout named in Settings is read to create that
  worktree and is otherwise only ever a git remote to it.
- **The suite may not shrink to make a gate pass.** Deleting a harness, or removing its `run` line
  from the dispatcher, turns every other gate green. `TestIntegrity` is the only thing standing
  between that and an open pull request, so it is a gate rather than a line in the prompt.
- **A pull request opens only on a green report.** `FeatureRequestRunner` runs the gates itself and
  reads its own verdict. The agent is asked to run them too and usually does, but an agent reporting on
  its own work is exactly the claim a gate exists to check.
- **A gate whose tool is missing is reported, never silently passed.** `VerificationReport.Outcome`
  is tri-state; a `skipped` gate reaches the detail pane and the pull request body verbatim.
- **One run at a time.** Two agents building against the same base would collide on the shared derived
  data and on every gate. `FeatureRequestCoordinator` owns a serial queue; extra requests wait as
  `.queued`.
- **A retry resumes the same session.** `--resume` carries what the first attempt worked out, so a
  correction is a correction rather than a second guess at the whole request. The same is true of a
  follow-up, which is why the session outlives the run that opened it.
- **A question can never write.** `AgentRunner.Mode.question` allowlists `Read`, `Grep` and `Glob`
  and denies every tool that edits or executes. The distinction is enforced by the invocation, not
  by asking the agent nicely, because ↵ has to be safe whatever the user typed.
- **A follow-up never opens a second pull request.** It lands on the branch that already exists and
  pushes; GitHub updates the open pull request itself. Anything that would branch again is a new
  request, not a change.
- **The switch is consent, and never rides a backup.** `featureRequestEnabled` is off by default and is
  in `SettingsBackupCoverage.deliberatelyExcluded`: an import must not grant an agent the ability to
  edit a checkout and push to it. The checkout path is not an `AppSettings` key at all — it names a
  folder that exists only on this Mac.
- **Only a failed run leaves a worktree behind.** It is the only copy of what the agent wrote, so it
  survives for the user to open. A successful run's worktree is removed once the branch is pushed.
- **Nothing survives the process.** A run cannot outlive the app that spawned it, so `FeatureRequestStore`
  settles anything still mid-flight into `.failed` on launch rather than showing a run that is not there.

## The pipeline

```text
typed sentence
  └─ worktree add -b feature/<slug>-<id>  origin/main
       └─ claude -p --permission-mode bypassPermissions      ← attempt 1
            └─ gates: purity → sync → test integrity → lint → tests → build
                 ├─ green  → commit → push → gh pr create
                 └─ red    → claude -p --resume <session>    ← attempt 2, 3, …
```

The gates are ordered cheapest first, and the run stops at the first failure: a grep answers instantly,
and the agent can only usefully be told about one gate at a time.

| Gate | What it runs | Why it is here |
| --- | --- | --- |
| Model purity | the `grep` from [AGENTS.md](../../AGENTS.md#before-you-finish) | a `Model/` file reaching for AppKit compiles fine and breaks the harnesses |
| Project sync | added sources vs. `project.pbxproj` | see [The xcodegen trap](#the-xcodegen-trap) |
| Test integrity | deleted or shrunk `Tests/` files, and `run-tests.sh` | see [Why the suite is guarded](#why-the-suite-is-guarded) |
| Lint | `./Scripts/lint.sh` | `skipped` when swiftlint is absent |
| Tests | `./Scripts/run-tests.sh` | the harnesses |
| Build | `xcodebuild -configuration Debug` | `skipped` when xcodebuild is absent |

### Why the suite is guarded

Every other gate checks that the suite *passes*, not that it still proves anything. The cheapest way
to turn a red run green is to delete the harness that was failing — or, more quietly, to drop its
`run` line from `Scripts/run-tests.sh`, which leaves the file in place and simply never dispatches it.
Both make all five other gates go green, and both would open a pull request.

`TestIntegrity` fails the run when a guarded file is deleted or ends up net shorter. Guarded means
`Tests/**.swift` plus the dispatcher itself. It reads the `git diff --numstat -M` the run already has,
so it costs nothing, and `-M` means a renamed harness reads as one edit rather than as a deletion.

It is deliberately strict: a legitimate test refactor that removes more lines than it adds will trip
it. That is the right trade for a gate whose entire job is to be un-negotiable, and the retry prompt
tells the agent to leave a genuinely wrong test failing and say so rather than delete it.

### The xcodegen trap

`project.yml` globs a folder, but generation bakes that glob into explicit file references. A source
file added without re-running `xcodegen generate` therefore compiles in the harnesses and is simply
*absent from the app* — the build passes, minus the new feature. Nothing else catches that, which is
why `ProjectSync` is a gate of its own rather than a note in the prompt.

`SubprocessRunner.environment` sets `DEVELOPER_DIR` to Xcode when it is installed, because
`xcode-select` on a machine set up for the CLI often points at CommandLineTools — which cannot build an
app target, and whose `swiftc` has no SwiftUI macro plugin for the harnesses either.

## Two ways to run the same CLI

`InstalledCLIProvider` (AI chat) and `AgentRunner` (here) both drive `claude`, and are deliberately
opposite:

| | `InstalledCLIProvider` | `AgentRunner` |
| --- | --- | --- |
| Tools | `--tools ""`, `--disallowedTools "*"` | every tool |
| Permissions | n/a — nothing to permit | `--permission-mode bypassPermissions` |
| Turns | `--max-turns 1` | up to the configured limit |
| Directory | a private empty workspace | the run's worktree |

The chat route is locked down because its output is prose the user reads. This one is unlocked because
its output is a diff the gates judge, in a directory that is discarded either way. Neither may borrow
the other's flags.

## Layout

| File | Holds |
| --- | --- |
| `Model/FeatureRequest.swift` | the record and its status; both persisted |
| `Model/FeatureRequestStore.swift` | the log, newest first, capped and settled on launch |
| `Model/FeatureBranch.swift` | slug, branch, title and pull request body — pure |
| `Model/AgentEvent.swift` | one stream line reduced to what the pipeline acts on |
| `Model/AgentEventDecoder.swift` | line-buffered `stream-json` decoding |
| `Model/VerificationReport.swift` | the gates, their verdicts and their digests |
| `Model/WorktreeChange.swift` | `git status --porcelain` parsing |
| `Model/ProjectSync.swift` | the added-sources-vs-project check |
| `Model/TestIntegrity.swift` | the suite-may-not-shrink check |
| `Model/PreviewRetention.swift` | which kept previews have expired — pure |
| `Model/AgentMessage.swift` | one turn of the conversation, and its tool calls |
| `Model/AgentMarkdownBlock.swift` | the markdown parser — a renamed copy of AI's |
| `Model/FeatureRequestPrompt.swift` | the initial and retry prompts |
| `Service/SubprocessRunner.swift` | one tool, one directory, drained as it runs |
| `Service/GitRunner.swift` | every `git` and `gh` call a run makes |
| `Service/AgentRunner.swift` | the `claude` invocation and its event stream |
| `Service/PreviewBuild.swift` | the preview channel, and keeping its app |
| `Service/QuestionRunner.swift` | the read-only turn, and the worktree behind it |
| `Service/FeatureRequestChatStore.swift` | transcripts, one file per request |
| `Service/VerificationRunner.swift` | the gates |
| `Service/FeatureRequestRunner.swift` | worktree → attempts → publish |
| `UI/FeatureRequestCoordinator.swift` | the action surface and the serial queue |
| `UI/FeatureRequestScreen.swift` | the `.featureRequest` palette mode |

## Asking a question

**Ask About This…** opens a conversation with the agent that built the request, rendered like AI
Chat but entirely separate from it. The one rule that shapes everything else:

- **↵ asks.** Read-only — `--allowedTools Read Grep Glob` with `Edit`, `Write`, `NotebookEdit`,
  `Bash` and `Task` all denied. No gates, no commit, no push. Whatever you type, nothing moves.
- **⌘↵ changes.** The follow-up path above, routed through the same queue as every run.

One key can only mean one thing, and guessing from the wording would sometimes edit a branch when
you were only asking. So the safe reading is the default and writing is the deliberate act.

**A new message interrupts rather than queues.** Sending while an answer is streaming cancels it
and starts yours; the partial reply stays in the transcript as what it managed to say. With an empty
field, ↵ is `Stop`. ⌘↵ interrupts too, and additionally supersedes a run already going on that
request rather than waiting behind it.

Interruption reaches the process: cancelling the task ends the `AsyncThrowingStream`, whose
`onTermination(.cancelled)` terminates the `claude` child. An answer that is abandoned stops costing
something. Each turn carries a token, so a cancelled one's teardown cannot clear the state of the
answer that replaced it, and its late events cannot land in the new reply.

A question runs against a **detached read-only worktree** of the branch, cut on the first question
and kept for the conversation, because "where does this go" deserves an answer from the files rather
than from what the session remembers writing. It is torn down when the conversation closes; the
transcript is what is worth keeping.

Transcripts live one JSON file per request under `feature-request-chats/`, loaded on demand — a
conversation is far larger than a request record, and `featureRequests` in `UserDefaults` has to stay
small. They are swept alongside previews when a request leaves the log.

### Why the transcript is duplicated

`AgentMarkdownBlock`, `AgentMarkdownView`, `AgentTranscriptView` and friends are copies of the AI
chat's, renamed. That is the deliberate trade, for the reason the Extensions rule gives for the same
situation: **neither feature may own the other's look.** Restyling AI Chat must not silently restyle
this, and this must be free to diverge — it already has, since the agent sends no images, no
documents and runs no web searches, so `AgentMessage` carries none of that.

The copies are otherwise byte-identical to their sources, so a fix worth having in both is a
readable diff rather than an archaeology exercise.

## Asking for a change

Trying a build usually produces an opinion about it, so a finished request can be amended rather than
only rebuilt. **Ask for a Change…** points the search field at that request; the next ↵ amends it
instead of starting a new one.

A follow-up is not a new request, and differs from one everywhere it matters:

| | A new request | A follow-up |
| --- | --- | --- |
| Branch | cut fresh from `origin/<base>` | the request's own, reopened with `-B` from the remote |
| Session | a new one | `--resume` on the session that built it |
| Prompt | `FeatureRequestPrompt.initial` | `.followUp`, which forbids rebuilding from scratch |
| Publishing | `gh pr create` | a push, which updates the pull request already open |

The session is persisted on the request for exactly this: a change asked for days later still lands in
the conversation that built the branch. If that session has aged out of `~/.claude`, the CLI exits
with "No conversation found" and the run retries once without it — the branch still holds the work and
the prompt still describes it, so a fresh session can finish the job.

`Build It Again` is the other half of this pair and deliberately does the opposite: it re-runs the
original wording as a brand new request, on a new branch, for when the first attempt went somewhere
you did not want.

## Trying a build before you merge

A pull request tells you what changed; it does not let you use it. So the build gate's artifact is
kept rather than discarded, and **Try It** on a finished request launches it.

It is built as its own channel — `Tinycast Preview`, `com.tinycast.app.preview` — by passing
`PRODUCT_NAME` and `PRODUCT_BUNDLE_IDENTIFIER` on the same `xcodebuild` line the gate already runs.
That is the pattern `release.yml` uses, and it is why `ClipboardTextHelper` pins `EXECUTABLE_NAME`:
a channel rename hits every target. The preview therefore launches *beside* whatever Tinycast is
already running instead of colliding with it for a bundle identifier.

The global chord belongs to whichever Tinycast registered it first, so a preview is opened from its
own menu-bar item rather than ⌥Space.

### Cleanup

`PreviewRetention` decides what goes; `FeatureRequestCoordinator.sweepPreviews()` runs it on launch,
after every finished run, and whenever a request is removed:

- the newest three verified runs keep their preview; older ones are dropped
- a preview whose request has left the log is an orphan and goes with it
- a preview that is currently running is skipped, and swept on the next pass instead
- once the last preview goes, so do the channel's own preferences and data — every preview shares
  the one bundle identifier, so that directory outlives any single build

Previews live in Caches, so macOS may purge them under disk pressure regardless.

## Storage

```text
~/Library/Application Support/<bundle-id>/feature-requests/<short-id>/   one run's worktree
~/Library/Caches/<bundle-id>/feature-request-build/                      shared derived data
~/Library/Caches/<bundle-id>/feature-request-previews/<short-id>/        the runnable build
~/Library/Application Support/<bundle-id>/feature-request-chats/<short-id>.json   a transcript
~/Library/Application Support/<bundle-id>/feature-request-questions/<short-id>/   read-only checkout
```

Derived data is shared across runs on purpose: a cold build of this app is minutes the retry loop can
keep, and the queue is serial so two runs never share it at once.

## Gotchas

- **`gh` must be authenticated.** `GH_PROMPT_DISABLED=1` is set, so an unauthenticated `gh` fails out
  with its own message instead of waiting on a prompt nothing can answer.
- **A prompt that needs a decision stops rather than guesses.** The agent is told to say so in its
  final message; that message becomes the attempt summary in the detail pane.
- **Child processes inherit Tinycast's TCC context.** The worktree lives in Application Support, so a
  run stays clear of the protected folders this would otherwise attribute to Tinycast.
- **`FeatureRequestPrompt` assembles the purity pattern from parts.** Writing the grep out in full
  would put the literal `import SwiftUI` in a `Model/` file and trip the very gate it describes.
