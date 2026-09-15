import SwiftUI

/// The store in the palette: every enabled registry searched, a detail screen under ↵.
struct ExtensionStoreScreen: PaletteScreen {
    let session: ExtensionStoreSession
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void

    /// Rows past which the next front-page batch is fetched, so the end never quite arrives.
    private static let loadMoreThreshold = 4

    var rows: [ExtensionListing] { session.rows }

    var primaryActionTitle: String { "Show Details" }

    private func listing(at selection: Int) -> ExtensionListing? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func activate(at selection: Int) {
        guard let listing = listing(at: selection) else { return }
        core.extensionCoordinator.showStoreDetails(listing)
    }

    /// ⌘↵ — install without reading the page first, as Raycast's own store does.
    func secondary(at selection: Int) -> Bool {
        guard let listing = listing(at: selection) else { return false }
        core.extensionCoordinator.installFromStore(listing)
        return true
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        guard shortcut == .copyName, let listing = listing(at: selection) else { return false }
        core.extensionCoordinator.copyStoreURL(listing)
        return true
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let listing = listing(at: selection) else { return nil }
        return ExtensionStoreActionsMenu.content(
            listing: listing, session: session, core: core, isDetail: false)
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            content(selection: selection, scroll: scroll)
                // Arrowing near the end asks for more, the same as scrolling there does.
                .onChange(of: selection) {
                    if selection >= rows.count - Self.loadMoreThreshold { session.loadMore() }
                })
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        if rows.isEmpty {
            emptyState
        } else {
            ExtensionStoreList(
                rows: rows,
                selectedID: listing(at: selection)?.id,
                sectionTitle: sectionTitle,
                notices: session.notices,
                isLoadingMore: session.isLoadingMore,
                installState: { session.installState(for: $0) },
                scroll: scroll,
                onSelect: { listing in vm.selection = rows.firstIndex(of: listing) ?? 0 },
                onActivate: { activate(at: vm.selection) },
                onActions: { listing in
                    if let index = rows.firstIndex(of: listing) { vm.selection = index }
                    openActions()
                },
                onReachEnd: { session.loadMore() })
        }
    }

    private var sectionTitle: String {
        if !session.isBrowsing { return "Results" }
        return session.category == .all ? "All Extensions" : session.category.title
    }

    /// Nothing is said while a query runs: the rows it replaces would only flash a message.
    @ViewBuilder
    private var emptyState: some View {
        if session.state == .loading, session.listings.isEmpty {
            Color.clear
        } else if let notice = session.notices.first, session.listings.isEmpty {
            EmptyResults(text: notice)
        } else if !session.listings.isEmpty {
            // The category sifted every loaded row; browsing can still fetch further down.
            EmptyResults(text: "No \(session.category.title) extensions in what has loaded")
                .onAppear { session.loadMore() }
        } else if session.isBrowsing {
            EmptyResults(text: "Type to search the store")
        } else {
            EmptyResults(text: "Nothing matches “\(vm.query.trimmingCharacters(in: .whitespaces))”")
        }
    }
}

/// The ⌘K rows for one listing, from the list and from its detail page alike.
@MainActor
enum ExtensionStoreActionsMenu {
    static func content(
        listing: ExtensionListing, session: ExtensionStoreSession, core: AppCore, isDetail: Bool
    ) -> PopoverMenuContent {
        let coordinator = core.extensionCoordinator
        var items: [PopoverMenuItem] = []
        if !isDetail {
            items.append(
                PopoverMenuItem(title: "Show Details", systemImage: "sidebar.left", shortcut: "↵") {
                    coordinator.showStoreDetails(listing)
                })
        }
        items.append(installItem(listing, session: session, coordinator: coordinator, isDetail: isDetail))
        if isDetail, let detail = session.detail(for: listing) {
            if !detail.screenshotURLs.isEmpty {
                items.append(
                    PopoverMenuItem(title: "Preview Screenshots", systemImage: "eye", shortcut: "⌘Y") {
                        session.isPreviewingScreenshot = true
                    })
            }
            if let readme = detail.readmeURL {
                items.append(
                    PopoverMenuItem(
                        title: "Open README", systemImage: "doc.text", startsSection: true
                    ) { coordinator.openStoreLink(readme) })
            }
            if let source = detail.sourceURL {
                items.append(
                    PopoverMenuItem(title: "View Source", systemImage: "chevron.left.forwardslash.chevron.right") {
                        coordinator.openStoreLink(source)
                    })
            }
        }
        if let page = listing.storeURL {
            items.append(
                PopoverMenuItem(
                    title: "Open in Browser", systemImage: "safari",
                    startsSection: !isDetail || session.detail(for: listing) == nil
                ) { coordinator.openStoreLink(page) })
            items.append(
                PopoverMenuItem(
                    title: "Copy Extension URL", systemImage: "doc.on.doc", shortcut: "⌥⌘C"
                ) { coordinator.copyStoreURL(listing) })
        }
        if !listing.authorHandle.isEmpty {
            items.append(
                PopoverMenuItem(title: "View Developer", systemImage: "person") {
                    coordinator.viewStoreDeveloper(listing)
                })
        }
        items.append(
            PopoverMenuItem(title: "Registries…", systemImage: "gearshape", startsSection: true) {
                coordinator.showRegistrySettings()
            })
        return PopoverMenuContent(header: listing.title, items: items)
    }

    private static func installItem(
        _ listing: ExtensionListing, session: ExtensionStoreSession,
        coordinator: ExtensionCoordinator, isDetail: Bool
    ) -> PopoverMenuItem {
        let shortcut = isDetail ? "↵" : "⌘↵"
        switch session.installState(for: listing) {
        case .installing(let message):
            return PopoverMenuItem(
                title: message, systemImage: "arrow.down.circle", isLoading: true, shortcut: shortcut
            ) {}
        case .installed:
            return PopoverMenuItem(title: "Installed", systemImage: "checkmark.circle") {}
        case .alreadyInstalled:
            return PopoverMenuItem(
                title: "Reinstall Extension", systemImage: "arrow.down.circle", shortcut: shortcut
            ) { coordinator.installFromStore(listing) }
        case .failed:
            return PopoverMenuItem(
                title: "Retry Install", systemImage: "arrow.clockwise", shortcut: shortcut
            ) { coordinator.installFromStore(listing) }
        case .idle:
            return PopoverMenuItem(
                title: "Install Extension", systemImage: "arrow.down.circle", shortcut: shortcut
            ) { coordinator.installFromStore(listing) }
        }
    }
}
