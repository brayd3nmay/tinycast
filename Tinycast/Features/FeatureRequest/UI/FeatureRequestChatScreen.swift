import SwiftUI

/// The conversation with one request's agent: ↵ asks, ⌘↵ changes, and only ⌘↵ can write.
struct FeatureRequestChatScreen: PaletteScreen {
    let request: FeatureRequest?
    let coordinator: FeatureRequestCoordinator
    let core: AppCore
    let vm: PaletteState

    /// The transcript is one surface, not a list of selectable rows.
    var rows: [AgentMessage] { [] }

    /// A conversation acts on what is typed, so ↵ must work with nothing selectable below it.
    var actsWithoutRows: Bool { true }

    private var typed: String { vm.query.trimmingCharacters(in: .whitespaces) }

    /// An empty field mid-answer means stop; anything typed means ask that instead, interrupting.
    var primaryActionTitle: String {
        typed.isEmpty && coordinator.isAnswering ? "Stop" : "Ask"
    }

    func hasPrimaryAction(at selection: Int) -> Bool {
        !typed.isEmpty || coordinator.isAnswering
    }

    func activate(at selection: Int) {
        guard !typed.isEmpty else {
            coordinator.stopAnswering()
            return
        }
        coordinator.ask(typed)
    }

    /// ⌘↵ — the only key in this screen that reaches the branch.
    func secondary(at selection: Int) -> Bool {
        guard !typed.isEmpty else { return false }
        coordinator.changeFromChat(typed)
        return true
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let request else { return nil }
        var items: [PopoverMenuItem] = []
        if coordinator.isAnswering {
            items.append(
                PopoverMenuItem(
                    title: typed.isEmpty ? "Stop" : "Stop and Ask Instead",
                    systemImage: "stop.circle"
                ) {
                    if typed.isEmpty { coordinator.stopAnswering() } else { coordinator.ask(typed) }
                })
        }
        if !typed.isEmpty, !coordinator.isAnswering {
            items.append(
                PopoverMenuItem(title: "Ask", systemImage: "questionmark.bubble", shortcut: "↵") {
                    coordinator.ask(typed)
                })
        }
        if !typed.isEmpty {
            items.append(
                PopoverMenuItem(
                    title: "Make the Change", systemImage: "arrow.triangle.branch", shortcut: "⌘↵"
                ) { coordinator.changeFromChat(typed) })
        }
        if coordinator.hasPreview(id: request.id) {
            items.append(
                PopoverMenuItem(title: "Try It", systemImage: "play.circle", startsSection: true) {
                    coordinator.tryPreview(id: request.id)
                })
        }
        if request.pullRequestURL != nil {
            items.append(
                PopoverMenuItem(
                    title: "Open Pull Request", systemImage: "arrow.up.forward.square",
                    startsSection: items.isEmpty
                ) { coordinator.openPullRequest(id: request.id) })
        }
        items.append(
            PopoverMenuItem(title: "Back to Requests", systemImage: "chevron.left", startsSection: true)
            {
                coordinator.closeChat()
                core.paletteCoordinator.togglePalette(mode: .featureRequest)
            })
        return PopoverMenuContent(header: request.title, items: items)
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content)
    }

    @ViewBuilder
    private var content: some View {
        if coordinator.conversation.isEmpty {
            EmptyResults(text: emptyMessage)
        } else {
            AgentTranscriptView(
                messages: coordinator.conversation, status: coordinator.answering)
        }
    }

    private var emptyMessage: String {
        guard let request else { return "No request open" }
        return "Ask about “\(request.title)” — ↵ answers, ⌘↵ changes it"
    }
}
