import SwiftUI

/// Request a Feature: the search field is the request, and the list below is every one so far.
struct FeatureRequestScreen: PaletteScreen {
    let store: FeatureRequestStore
    let coordinator: FeatureRequestCoordinator
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void

    private var metrics: InterfaceMetrics { core.settings.interfaceSize.metrics }

    enum Row: Identifiable {
        /// The typed sentence, offered as the thing ↵ acts on before any history below it.
        case submit(String)
        /// The same, but aimed at a request that already has a branch and a pull request.
        case amend(FeatureRequest, String)
        case request(FeatureRequest)

        var id: String {
            switch self {
            case .submit: return "submit"
            case .amend: return "amend"
            case .request(let request): return request.id.uuidString
            }
        }
    }

    var rows: [Row] {
        let typed = vm.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let history = store.requests.map(Row.request)
        // Composing a change: the field belongs to that request, so it never filters the list.
        if let id = coordinator.pendingFollowUp, let target = store.request(id: id) {
            return typed.isEmpty ? history : [.amend(target, typed)] + history
        }
        guard !typed.isEmpty else { return history }
        return [.submit(typed)] + history.filter {
            guard case .request(let request) = $0 else { return false }
            return request.prompt.localizedCaseInsensitiveContains(typed)
        }
    }

    /// Reads the selection because the two row kinds do genuinely different things on ↵.
    var primaryActionTitle: String {
        switch row(at: vm.selection) {
        case .submit: return "Build Feature"
        case .amend: return "Make the Change"
        case .request(let request):
            return request.pullRequestURL == nil ? "Show Request" : "Open Pull Request"
        case nil: return "Build Feature"
        }
    }

    private func row(at selection: Int) -> Row? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func activate(at selection: Int) {
        switch row(at: selection) {
        case .submit(let prompt): coordinator.submit(prompt)
        case .amend(_, let change): coordinator.submitFollowUp(change)
        case .request(let request):
            if request.pullRequestURL != nil { coordinator.openPullRequest(id: request.id) }
        case nil: break
        }
    }

    func secondary(at selection: Int) -> Bool { false }

    func actions(at selection: Int) -> PopoverMenuContent? {
        switch row(at: selection) {
        case .submit(let prompt):
            return PopoverMenuContent(
                header: "New Request",
                items: [
                    PopoverMenuItem(title: "Build Feature", systemImage: "hammer", shortcut: "↵") {
                        coordinator.submit(prompt)
                    },
                    settingsItem
                ])
        case .amend(let request, let change):
            return PopoverMenuContent(
                header: "Change “" + request.title + "”",
                items: [
                    PopoverMenuItem(
                        title: "Make the Change", systemImage: "arrow.triangle.branch", shortcut: "↵"
                    ) { coordinator.submitFollowUp(change) },
                    PopoverMenuItem(title: "Cancel", systemImage: "xmark") {
                        coordinator.cancelFollowUp()
                    }
                ])
        case .request(let request):
            return PopoverMenuContent(header: request.title, items: items(for: request))
        case nil:
            return PopoverMenuContent(header: "Requests", items: [settingsItem])
        }
    }

    private func items(for request: FeatureRequest) -> [PopoverMenuItem] {
        var items: [PopoverMenuItem] = []
        if request.pullRequestURL != nil {
            items.append(
                PopoverMenuItem(
                    title: "Open Pull Request", systemImage: "arrow.up.forward.square", shortcut: "↵"
                ) { coordinator.openPullRequest(id: request.id) })
        }
        if request.acceptsFollowUp {
            items.append(
                PopoverMenuItem(
                    title: "Ask About This…", systemImage: "bubble.left.and.text.bubble.right"
                ) { coordinator.openChat(id: request.id) })
            items.append(
                PopoverMenuItem(title: "Ask for a Change…", systemImage: "arrow.triangle.branch") {
                    coordinator.beginFollowUp(id: request.id)
                })
        }
        if coordinator.hasPreview(id: request.id) {
            items.append(
                PopoverMenuItem(title: "Try It", systemImage: "play.circle") {
                    coordinator.tryPreview(id: request.id)
                })
        }
        items.append(
            PopoverMenuItem(title: "Copy Request", systemImage: "doc.on.doc") {
                coordinator.copyPrompt(id: request.id)
            })
        if request.status.isRunning {
            items.append(
                PopoverMenuItem(
                    title: "Cancel Run", systemImage: "stop.circle", startsSection: true
                ) { coordinator.cancel(id: request.id) })
        } else {
            items.append(
                PopoverMenuItem(
                    title: "Build It Again", systemImage: "arrow.clockwise", startsSection: true
                ) { coordinator.retry(id: request.id) })
        }
        if request.worktreePath != nil {
            items.append(
                PopoverMenuItem(title: "Show Worktree in Finder", systemImage: "folder") {
                    coordinator.revealWorktree(id: request.id)
                })
        }
        items.append(
            PopoverMenuItem(title: "Remove", systemImage: "trash", startsSection: true) {
                coordinator.remove(id: request.id)
            })
        items.append(
            PopoverMenuItem(title: "Clear Finished", systemImage: "eraser") {
                coordinator.clearFinished()
            })
        items.append(settingsItem)
        return items
    }

    private var settingsItem: PopoverMenuItem {
        PopoverMenuItem(title: "Feature Request Settings…", systemImage: "gearshape", startsSection: true) {
            core.paletteCoordinator.hidePalette(restoreFocus: false)
            core.settingsCoordinator.showSettings(tab: .featureRequest)
        }
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        if rows.isEmpty {
            EmptyResults(text: "Describe the feature you want and press ↵")
        } else {
            HStack(spacing: 0) {
                FeatureRequestList(
                    rows: rows, selectedID: row(at: selection)?.id, activity: coordinator.activity,
                    scroll: scroll,
                    onSelect: { row in vm.selection = rows.firstIndex { $0.id == row.id } ?? 0 },
                    onActivate: { activate(at: vm.selection) },
                    onActions: { row in
                        if let index = rows.firstIndex(where: { $0.id == row.id }) {
                            vm.selection = index
                        }
                        openActions()
                    }
                )
                .frame(width: metrics.size.clipboardListWidth)
                Rectangle().fill(Theme.Colors.separator).frame(width: Theme.Size.hairline)
                FeatureRequestDetail(
                    row: row(at: selection), activity: coordinator.activity)
            }
        }
    }
}
