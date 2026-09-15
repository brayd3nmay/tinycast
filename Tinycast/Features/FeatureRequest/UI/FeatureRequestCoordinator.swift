import AppKit

/// Request a Feature: takes the typed sentence, and owns the one-at-a-time queue behind it.
@MainActor
@Observable
final class FeatureRequestCoordinator {
    private let store: FeatureRequestStore
    private let chat: FeatureRequestChatStore
    private let settings: FeatureRequestSettingsStore
    private let appSettings: AppSettings
    private let palette: PaletteState
    private let appIndex: AppIndex
    private let paletteCoordinator: PaletteCoordinator
    private let settingsCoordinator: SettingsCoordinator
    private unowned let core: AppCore

    /// The agent's latest line per request. Transient on purpose: none of it belongs in the log.
    private(set) var activity: [UUID: String] = [:]
    /// The request the typed text will amend, rather than start a new request of its own.
    private(set) var pendingFollowUp: UUID?
    /// One run at a time — two agents building against the same base would collide on every gate.
    @ObservationIgnored private var runTask: Task<Void, Never>?

    init(
        store: FeatureRequestStore, chat: FeatureRequestChatStore,
        settings: FeatureRequestSettingsStore, appSettings: AppSettings,
        palette: PaletteState, appIndex: AppIndex, paletteCoordinator: PaletteCoordinator,
        settingsCoordinator: SettingsCoordinator, core: AppCore
    ) {
        self.store = store
        self.chat = chat
        self.settings = settings
        self.appSettings = appSettings
        self.palette = palette
        self.appIndex = appIndex
        self.paletteCoordinator = paletteCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.core = core
    }

    /// Follows the switch: turning the feature off must also stop whatever it already started.
    func applyEnabled() {
        let isEnabled = appSettings.featureRequestEnabled
        appIndex.setCommandsVisible([.requestFeature, .featureRequests], isEnabled)
        // Sweeps previews whose request is gone, including any left by a run that never finished.
        sweepPreviews()
        guard !isEnabled else { return }
        runTask?.cancel()
        if paletteCoordinator.isShowing(.featureRequest) {
            paletteCoordinator.hidePalette(restoreFocus: false)
        }
    }

    // MARK: - Surface

    func showRequests() {
        paletteCoordinator.togglePalette(mode: .featureRequest)
    }

    /// Nothing is queued before the checkout is set, so the failure lands in Settings, not mid-run.
    func submit(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, appSettings.featureRequestEnabled else { return }
        guard settings.isConfigured else {
            paletteCoordinator.hidePalette(restoreFocus: false)
            core.showMessage("Choose your Tinycast checkout first.", tone: .danger)
            settingsCoordinator.showSettings(tab: .featureRequest)
            return
        }
        let id = UUID()
        store.add(
            FeatureRequest(
                id: id, prompt: trimmed, branch: FeatureBranch.name(prompt: trimmed, id: id)))
        // The sentence is now a row in the list below, so the field starts over.
        palette.query = ""
        palette.selection = 0
        startNext()
    }

    // MARK: - Conversation

    /// The request whose conversation is open, if any.
    private(set) var chattingAbout: UUID?
    /// The agent's current line while a question is in flight; nil when nothing is running.
    private(set) var answering: String?
    @ObservationIgnored private var questionTask: Task<Void, Never>?
    /// Identifies the answer in flight, so an interrupted one cannot tear down its successor.
    @ObservationIgnored private var questionToken: UUID?
    @ObservationIgnored private var streamingReply: UUID?

    var conversation: [AgentMessage] { chat.messages }

    /// The request the open conversation is about, for the screen to title itself with.
    var openRequest: FeatureRequest? { chattingAbout.flatMap(store.request(id:)) }

    var isAnswering: Bool { answering != nil }

    /// Opens the conversation for a request and loads whatever has already been said.
    func openChat(id: UUID) {
        guard let request = store.request(id: id), request.acceptsFollowUp else { return }
        chattingAbout = id
        chat.load(request)
        palette.query = ""
        palette.selection = 0
        paletteCoordinator.togglePalette(mode: .featureRequestChat)
    }

    /// Leaves the conversation; the transcript is kept, the checkout behind it is not.
    func closeChat() {
        guard let id = chattingAbout, let request = store.request(id: id) else { return }
        stopAnswering()
        chattingAbout = nil
        chat.close()
        if let repository = settings.repository {
            Task.detached {
                await QuestionRunner.discardWorktree(for: request, repository: repository)
            }
        }
    }

    /// Ends the answer in flight, keeping whatever it had already said.
    func stopAnswering() {
        questionTask?.cancel()
        questionTask = nil
        questionToken = nil
        answering = nil
        if let reply = streamingReply {
            chat.update(reply) { message in
                guard message.state == .streaming else { return }
                for index in message.toolCalls.indices { message.toolCalls[index].isRunning = false }
                if message.text.isEmpty { message.text = "Stopped." }
                message.state = .complete
            }
        }
        streamingReply = nil
    }

    /// ↵ in a conversation. Read-only by construction: this path can never reach the branch.
    func ask(_ question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let id = chattingAbout,
            let request = store.request(id: id), let configuration = settings.configuration
        else { return }
        // A new message interrupts the answer in flight rather than queueing behind it.
        stopAnswering()
        chat.append(AgentMessage(role: .user, text: trimmed, intent: .question))
        let reply = chat.append(
            AgentMessage(role: .agent, text: "", state: .streaming, intent: .question))
        palette.query = ""
        answering = "Thinking…"

        let token = UUID()
        questionToken = token
        streamingReply = reply
        let projector = AgentTranscript(messageID: reply, token: token)
        let runner = QuestionRunner(configuration: configuration) { [weak self] event in
            Task { @MainActor in self?.absorb(event, into: projector) }
        }
        questionTask = Task { [weak self] in
            do {
                _ = try await runner.ask(trimmed, for: request)
                self?.chat.update(reply) { if $0.state == .streaming { $0.state = .complete } }
            } catch is CancellationError {
                self?.chat.update(reply) { if $0.state == .streaming { $0.state = .complete } }
            } catch {
                self?.chat.update(reply) {
                    guard $0.state == .streaming else { return }
                    $0.text = error.localizedDescription
                    $0.state = .failed
                }
            }
            // Only if this is still the current answer; an interrupted one owns none of this state.
            guard let self, self.questionToken == token else { return }
            self.answering = nil
            self.questionTask = nil
            self.streamingReply = nil
        }
    }

    /// ⌘↵ in a conversation: the one path that writes, routed into the queue the runs use.
    func changeFromChat(_ change: String) {
        let trimmed = change.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let id = chattingAbout else { return }
        stopAnswering()
        // Supersedes a run already going on this request rather than queueing behind it.
        if store.request(id: id)?.status.isRunning == true { cancel(id: id) }
        chat.append(AgentMessage(role: .user, text: trimmed, intent: .change))
        pendingFollowUp = id
        submitFollowUp(trimmed)
        paletteCoordinator.togglePalette(mode: .featureRequest)
    }

    private func absorb(_ event: AgentEvent, into projector: AgentTranscript) {
        guard questionToken == projector.token else { return }
        switch event {
        case .started:
            break
        case .narration(let line):
            answering = line
            chat.update(projector.messageID) { $0.text += ($0.text.isEmpty ? "" : "\n\n") + line }
        case .activity(let label):
            answering = label
            chat.update(projector.messageID) { message in
                for index in message.toolCalls.indices { message.toolCalls[index].isRunning = false }
                message.toolCalls.append(
                    AgentToolCall(label: label, textOffset: message.text.count))
            }
        case .finished(let result):
            chat.update(projector.messageID) { message in
                for index in message.toolCalls.indices { message.toolCalls[index].isRunning = false }
                if message.text.isEmpty { message.text = result.summary }
                message.state = result.isError ? .failed : .complete
            }
        }
    }

    /// Points the search field at an existing request; the next ↵ amends it instead of branching.
    func beginFollowUp(id: UUID) {
        guard store.request(id: id)?.acceptsFollowUp == true else { return }
        pendingFollowUp = id
        palette.query = ""
        palette.selection = 0
    }

    func cancelFollowUp() {
        pendingFollowUp = nil
    }

    /// Nil unless a follow-up is being composed, which is when the field stops being a new request.
    var searchPlaceholder: String? {
        guard let pendingFollowUp, let request = store.request(id: pendingFollowUp) else {
            return nil
        }
        return "Change “\(request.title)”…"
    }

    func submitFollowUp(_ change: String) {
        let trimmed = change.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, appSettings.featureRequestEnabled,
            let id = pendingFollowUp, let request = store.request(id: id), request.acceptsFollowUp
        else { return }
        store.update(id: id) { request in
            request.followUps.append(trimmed)
            request.status = .queued
        }
        pendingFollowUp = nil
        palette.query = ""
        palette.selection = 0
        startNext()
    }

    func retry(id: UUID) {
        guard let request = store.request(id: id) else { return }
        submit(request.prompt)
    }

    func cancel(id: UUID) {
        guard let request = store.request(id: id) else { return }
        if request.status.isRunning {
            runTask?.cancel()
            return
        }
        store.update(id: id) { $0.status = .cancelled }
    }

    func remove(id: UUID) {
        if pendingFollowUp == id { pendingFollowUp = nil }
        cancel(id: id)
        activity[id] = nil
        store.remove(id: id)
        sweepPreviews()
    }

    func clearFinished() {
        store.clearFinished()
        sweepPreviews()
    }

    func openPullRequest(id: UUID) {
        guard let url = store.request(id: id)?.pullRequestURL else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        NSWorkspace.shared.open(url)
    }

    func copyPrompt(id: UUID) {
        guard let request = store.request(id: id) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(request.prompt, forType: .string)
        core.showMessage("Copied the request.")
    }

    /// True only while the verified build is still on disk; the row hides the action otherwise.
    func hasPreview(id: UUID) -> Bool {
        guard let request = store.request(id: id), request.isVerified else { return false }
        return PreviewBuild.exists(for: request.shortID)
    }

    /// Opens beside whatever Tinycast is already running — its own channel, so nothing is displaced.
    func tryPreview(id: UUID) {
        guard let request = store.request(id: id), hasPreview(id: request.id) else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(
            at: PreviewBuild.location(for: request.shortID), configuration: configuration
        ) { [weak self] _, error in
            Task { @MainActor in
                guard let self, let error else {
                    self?.core.showMessage("Opened \(PreviewBuild.productName).")
                    return
                }
                self.core.showMessage(error.localizedDescription, tone: .danger)
            }
        }
    }

    /// Keeps the newest few, drops anything whose request is gone, and never deletes a running app.
    private func sweepPreviews() {
        let live = store.requests.filter(\.isVerified).map(\.shortID)
        let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: PreviewBuild.bundleID)
            .compactMap { $0.bundleURL?.deletingLastPathComponent().lastPathComponent }
            .first
        for expired in PreviewRetention.expired(
            onDisk: PreviewBuild.onDisk(), live: live, running: running)
        {
            PreviewBuild.discard(expired)
        }
        // The channel's own settings and data are shared, so they go once the last preview does.
        if running == nil, PreviewBuild.onDisk().isEmpty { PreviewBuild.discardChannelData() }
        chat.sweep(keeping: store.requests.map(\.shortID))
    }

    /// Only a failed run still has one: a successful run's worktree is removed once it is pushed.
    func revealWorktree(id: UUID) {
        guard let path = store.request(id: id)?.worktreePath else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    // MARK: - The queue

    /// Reads the switch too: cancelling the active run must not let the queue behind it through.
    private func startNext() {
        guard appSettings.featureRequestEnabled else { return }
        guard runTask == nil, let next = store.queued.last else { return }
        runTask = Task { [weak self] in
            await self?.run(next.id)
            self?.runTask = nil
            self?.startNext()
        }
    }

    private func run(_ id: UUID) async {
        guard let request = store.request(id: id), let configuration = settings.configuration else {
            return
        }
        let runner = FeatureRequestRunner(configuration: configuration) { [weak self] progress in
            Task { @MainActor in self?.apply(progress, to: id) }
        }
        do {
            // A request with a pull request and an unbuilt follow-up is amending, not starting over.
            let change = request.isVerified ? request.followUps.last : nil
            let url = try await runner.run(request, change: change)
            finish(id, status: url.map { .opened(url: $0) } ?? .pushed)
        } catch is CancellationError {
            finish(id, status: .cancelled)
        } catch {
            finish(id, status: .failed(reason: error.localizedDescription))
        }
    }

    private func apply(_ progress: FeatureRequestRunner.Progress, to id: UUID) {
        switch progress {
        case .status(let status):
            store.update(id: id) { $0.status = status }
        case .activity(let line):
            activity[id] = line
        case .worktree(let url):
            store.update(id: id) { $0.worktreePath = url.path }
        case .session(let sessionID):
            store.update(id: id) { $0.sessionID = sessionID }
        case .attempt(let attempt):
            store.update(id: id) { request in
                if attempt.id == 1 { request.attempts.removeAll() }
                if let index = request.attempts.firstIndex(where: { $0.id == attempt.id }) {
                    request.attempts[index] = attempt
                } else {
                    request.attempts.append(attempt)
                }
            }
        }
    }

    private func finish(_ id: UUID, status: FeatureRequestStatus) {
        activity[id] = nil
        // Re-queued while this run was tearing down: the new job owns the status now.
        guard store.request(id: id)?.status != .queued else { return }
        store.update(id: id) { request in
            request.status = status
            // The worktree is gone once a run succeeds; only a failure leaves one to open.
            if case .failed = status {} else { request.worktreePath = nil }
        }
        announce(status, for: id)
        sweepPreviews()
    }

    private func announce(_ status: FeatureRequestStatus, for id: UUID) {
        guard let title = store.request(id: id)?.title else { return }
        switch status {
        case .opened:
            core.showMessage("Pull request opened for “\(title)”.")
        case .pushed:
            core.showMessage("Branch pushed for “\(title)”.")
        case .failed(let reason):
            core.showMessage(reason, tone: .danger)
        case .cancelled, .queued, .preparing, .implementing, .verifying, .publishing:
            break
        }
    }
}
