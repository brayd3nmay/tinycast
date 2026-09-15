import SwiftUI

/// The Store's result rows. Written here rather than shared: a registry row is not a launcher row.
struct ExtensionStoreList: View {
    @Environment(\.metrics) private var metrics
    let listings: [ExtensionListing]
    let session: ExtensionStoreSession
    let installedNames: Set<String>
    let selectedID: ExtensionListing.ID?
    let scroll: ScrollIntent
    let onSelect: (ExtensionListing) -> Void
    let onActivate: () -> Void
    let onActions: (ExtensionListing) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(listings) { listing in
                        ExtensionStoreRow(
                            listing: listing, selected: listing.id == selectedID,
                            install: session.installState(for: listing),
                            isInstalled: installedNames.contains(listing.name)
                        )
                        .selectionFrame(listing.id == selectedID)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(listing) }
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                onSelect(listing)
                                onActivate()
                            }
                        )
                        .onRightClick { onActions(listing) }
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selectedID, atOrigin: selectedID == listings.first?.id, proxy: proxy)
        }
    }
}

private struct ExtensionStoreRow: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.isDarkAppearance) private var isDark
    let listing: ExtensionListing
    let selected: Bool
    let install: ExtensionStoreSession.InstallState?
    let isInstalled: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            ExtensionIconView(
                resolved: listing.iconURL(isDark: isDark).map {
                    ExtensionImage.Resolved(source: .remote($0))
                })
            VStack(alignment: .leading, spacing: metrics.spacing.xxs) {
                Text(listing.title)
                    .font(metrics.typography.rowTitle)
                    .lineLimit(1)
                Text(listing.author.isEmpty ? listing.registryName : listing.author)
                    .font(metrics.typography.keyCap)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: metrics.spacing.sm)
            trailing
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill)
        )
        .armedHover($hovered)
    }

    /// One slot: what the install is doing outranks what the row would otherwise say about itself.
    @ViewBuilder
    private var trailing: some View {
        switch install {
        case .installing:
            ProgressView().controlSize(.small)
        case .failed:
            Image(systemName: "exclamationmark.triangle")
                .font(metrics.typography.keyCap)
                .foregroundStyle(.orange)
        case .installed:
            installedMark
        case nil:
            if isInstalled {
                installedMark
            } else if let downloadCount = listing.downloadCount, downloadCount > 0 {
                Text(ExtensionListing.abbreviate(downloadCount))
                    .font(metrics.typography.keyCap)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .monospacedDigit()
            }
        }
    }

    private var installedMark: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(metrics.typography.keyCap)
            .foregroundStyle(.green)
            .accessibilityLabel("Installed")
    }
}

/// Nothing to list yet — which of the four reasons it is decides what the screen should say.
struct ExtensionStoreEmptyState: View {
    @Environment(\.metrics) private var metrics
    let query: String
    let state: ExtensionStoreSession.State
    let notices: [String]
    let registries: [ExtensionRegistry]

    var body: some View {
        VStack(spacing: metrics.spacing.md) {
            Image(systemName: symbol)
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)
            Text(title).foregroundStyle(.secondary)
            if !notices.isEmpty {
                Text(notices.joined(separator: " · "))
                    .font(metrics.typography.keyCap)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, metrics.spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hasRegistry: Bool { registries.contains { $0.isEnabled } }

    private var symbol: String {
        hasRegistry ? "storefront" : "tray"
    }

    private var title: String {
        guard hasRegistry else {
            return "No registries are enabled — turn one on in Settings › Extensions."
        }
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Search the store by name, or by what an extension does."
        }
        return state == .searching ? "Searching…" : "Nothing matches “\(query)”."
    }
}
