import SwiftUI

/// The Store as a palette screen: one list over every enabled registry, previewed beside it.
struct ExtensionStoreScreen: PaletteScreen {
    let session: ExtensionStoreSession
    let extensions: ExtensionManager
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void

    private var metrics: InterfaceMetrics { core.settings.interfaceSize.metrics }

    var rows: [ExtensionListing] { session.results }

    var primaryActionTitle: String {
        guard let listing = listing(at: vm.selection) else { return "Install" }
        return isInstalled(listing) ? "Reinstall" : "Install"
    }

    private func listing(at selection: Int) -> ExtensionListing? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    private func isInstalled(_ listing: ExtensionListing) -> Bool {
        if case .installed = session.installState(for: listing) { return true }
        return extensions.installed.contains { $0.manifest.name == listing.name }
    }

    func activate(at selection: Int) {
        guard let listing = listing(at: selection) else { return }
        core.extensionCoordinator.installFromStore(listing)
    }

    /// ⌘↵ — the extension's own page, which is where its screenshots and issues are.
    func secondary(at selection: Int) -> Bool {
        guard let listing = listing(at: selection), listing.pageURL != nil else { return false }
        core.extensionCoordinator.openStorePage(listing)
        return true
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let listing = listing(at: selection) else { return nil }
        return ExtensionStoreActionsMenu.content(
            listing: listing, isInstalled: isInstalled(listing), core: core,
            installed: extensions.installed.first { $0.manifest.name == listing.name })
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        if rows.isEmpty {
            ExtensionStoreEmptyState(
                query: vm.query, state: session.state, notices: session.notices,
                registries: core.settings.extensionRegistries)
        } else {
            let selected = listing(at: selection)
            HStack(spacing: 0) {
                ExtensionStoreList(
                    listings: rows, session: session, installedNames: installedNames,
                    selectedID: selected?.id, scroll: scroll,
                    onSelect: { listing in vm.selection = rows.firstIndex(of: listing) ?? 0 },
                    onActivate: { activate(at: vm.selection) },
                    onActions: { listing in
                        if let index = rows.firstIndex(of: listing) { vm.selection = index }
                        openActions()
                    }
                )
                .frame(width: metrics.size.clipboardListWidth)
                Rectangle().fill(Theme.Colors.separator).frame(width: Theme.Size.hairline)
                ExtensionStoreDetail(
                    listing: selected, session: session,
                    isInstalled: selected.map(isInstalled) ?? false)
            }
        }
    }

    private var installedNames: Set<String> {
        Set(extensions.installed.map(\.manifest.name))
    }
}

/// The rows ⌘K offers; installing and uninstalling both run through the coordinator.
@MainActor
enum ExtensionStoreActionsMenu {
    static func content(
        listing: ExtensionListing, isInstalled: Bool, core: AppCore, installed: InstalledExtension?
    ) -> PopoverMenuContent {
        let coordinator = core.extensionCoordinator
        var items = [
            PopoverMenuItem(
                title: isInstalled ? "Reinstall" : "Install",
                systemImage: isInstalled ? "arrow.trianglehead.clockwise" : "arrow.down.circle",
                shortcut: "↵"
            ) { coordinator.installFromStore(listing) }
        ]
        if listing.pageURL != nil {
            items.append(
                PopoverMenuItem(
                    title: "Open in Browser", systemImage: "globe", startsSection: true,
                    shortcut: "⌘↵"
                ) { coordinator.openStorePage(listing) })
            items.append(
                PopoverMenuItem(title: "Copy Link", systemImage: "link") {
                    coordinator.copyStoreLink(listing)
                })
        }
        if let installed {
            items.append(
                PopoverMenuItem(
                    title: "Uninstall", systemImage: "trash", startsSection: true,
                    isDestructive: true
                ) { coordinator.confirmUninstall(installed) })
        }
        return PopoverMenuContent(header: listing.title, items: items)
    }
}
