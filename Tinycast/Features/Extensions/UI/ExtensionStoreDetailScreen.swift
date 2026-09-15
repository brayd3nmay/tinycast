import SwiftUI

/// One listing's page: ↵ installs, ←/→ walk the screenshots, ⌘Y opens one full size.
struct ExtensionStoreDetailScreen: PaletteScreen {
    let session: ExtensionStoreSession
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void

    struct Screenshot: Identifiable, Equatable {
        let url: URL
        var id: String { url.absoluteString }
    }

    var listing: ExtensionListing? { session.opened }

    private var detail: ExtensionStoreDetail? { listing.flatMap(session.detail(for:)) }

    /// The screenshots are what the selection walks; the page itself is one surface.
    var rows: [Screenshot] { (detail?.screenshotURLs ?? []).map(Screenshot.init) }

    /// The page has no search; the header keeps only the chevron back to the results.
    var hidesSearchField: Bool { true }

    /// Installing is the page's action, whether or not it has a screenshot to land on.
    var actsWithoutRows: Bool { true }

    private var installState: ExtensionStoreSession.InstallState {
        listing.map(session.installState(for:)) ?? .idle
    }

    var primaryActionTitle: String {
        switch installState {
        case .installing(let message): return message
        case .installed: return "Installed"
        case .alreadyInstalled: return "Reinstall Extension"
        case .failed: return "Retry Install"
        case .idle: return "Install Extension"
        }
    }

    /// The pill stays through an install, reading its progress; only ↵ goes quiet meanwhile.
    func hasPrimaryAction(at selection: Int) -> Bool { listing != nil }

    func activate(at selection: Int) {
        guard let listing else { return }
        switch installState {
        case .installing, .installed: return
        case .alreadyInstalled, .failed, .idle:
            core.extensionCoordinator.installFromStore(listing)
        }
    }

    func secondary(at selection: Int) -> Bool { false }

    /// ↑/↓ have no rows to walk here, so they stay put; ←/→ step the screenshot strip.
    func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int? {
        switch axis {
        case .vertical: return selection
        case .horizontal:
            let count = rows.count
            guard count > 0 else { return nil }
            return min(max(selection + delta, 0), count - 1)
        }
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        switch shortcut {
        case .quickLook:
            guard !rows.isEmpty else { return false }
            session.isPreviewingScreenshot.toggle()
            return true
        case .copyName:
            guard let listing else { return false }
            core.extensionCoordinator.copyStoreURL(listing)
            return true
        default:
            return false
        }
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let listing else { return nil }
        return ExtensionStoreActionsMenu.content(
            listing: listing, session: session, core: core, isDetail: true)
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection))
    }

    @ViewBuilder
    private func content(selection: Int) -> some View {
        if let listing {
            let rows = rows
            ExtensionStoreDetailView(
                listing: listing,
                detail: detail,
                failure: session.detailFailure(for: listing),
                installState: installState,
                selectedScreenshot: rows.indices.contains(selection) ? selection : nil,
                onSelectScreenshot: { index in
                    vm.selection = index
                    session.isPreviewingScreenshot = true
                },
                onOpenLink: { core.extensionCoordinator.openStoreLink($0) },
                onViewDeveloper: { core.extensionCoordinator.viewStoreDeveloper(listing) }
            )
            .overlay {
                if session.isPreviewingScreenshot, rows.indices.contains(selection) {
                    ExtensionStoreScreenshotPreview(
                        title: listing.title, urls: rows.map(\.url), index: selection,
                        onStep: { delta in
                            vm.selection = min(max(selection + delta, 0), rows.count - 1)
                        },
                        onClose: { session.isPreviewingScreenshot = false })
                }
            }
        } else {
            EmptyResults(text: "No extension open")
        }
    }
}
