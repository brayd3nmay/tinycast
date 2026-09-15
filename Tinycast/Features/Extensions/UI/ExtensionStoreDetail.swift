import SwiftUI

/// The preview beside the Store's list: what the extension is, what it runs, and its README.
struct ExtensionStoreDetail: View {
    @Environment(\.metrics) private var metrics
    let listing: ExtensionListing?
    let session: ExtensionStoreSession
    let isInstalled: Bool

    var body: some View {
        Group {
            if let listing {
                ScrollView {
                    VStack(alignment: .leading, spacing: metrics.spacing.md) {
                        ExtensionStoreHeader(listing: listing, isInstalled: isInstalled)
                        installNote(listing)
                        commands(listing)
                        readme(listing)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, metrics.spacing.lg)
                    .padding(.vertical, metrics.spacing.md)
                    .hideNativeScrollers()
                }
                .edgeDissolve()
                .thinScrollbar()
                // Cancelled when the selection moves on, which is what debounces the fetch.
                .task(id: listing.id) { await session.loadReadme(for: listing) }
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The only place a failed install's words are readable in full; the row only has a glyph.
    @ViewBuilder
    private func installNote(_ listing: ExtensionListing) -> some View {
        switch session.installState(for: listing) {
        case .installing(let message):
            Label(message, systemImage: "arrow.down.circle")
                .font(metrics.typography.keyCap)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(metrics.typography.keyCap)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        case .installed:
            Label("Installed — its commands are in the launcher now.", systemImage: "checkmark.circle")
                .font(metrics.typography.keyCap)
                .foregroundStyle(.secondary)
        case nil:
            if listing.needsBuild {
                Label(
                    "This registry serves source: installing runs your package manager and a build.",
                    systemImage: "hammer"
                )
                .font(metrics.typography.keyCap)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func commands(_ listing: ExtensionListing) -> some View {
        if !listing.commands.isEmpty {
            VStack(alignment: .leading, spacing: metrics.spacing.sm) {
                Text("Commands")
                    .font(metrics.typography.sectionHeader)
                    .foregroundStyle(.secondary)
                ForEach(listing.commands) { command in
                    VStack(alignment: .leading, spacing: metrics.spacing.xxs) {
                        Text(command.title).font(metrics.typography.rowTitle)
                        if !command.summary.isEmpty {
                            Text(command.summary)
                                .font(metrics.typography.keyCap)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(metrics.spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: metrics.radius.menu, style: .continuous)
                            .fill(ExtensionColors.detailCardFill))
                }
            }
        }
    }

    @ViewBuilder
    private func readme(_ listing: ExtensionListing) -> some View {
        switch session.readme(for: listing) {
        case .text(let markdown):
            Rectangle().fill(Theme.Colors.separator).frame(height: Theme.Size.hairline)
            ExtensionMarkdownView(markdown: markdown)
        case .loading:
            Text("Loading README…")
                .font(metrics.typography.keyCap)
                .foregroundStyle(.secondary)
        case .unavailable, nil:
            EmptyView()
        }
    }
}

/// Icon, title and the facts a listing carries about itself, above everything else in the pane.
private struct ExtensionStoreHeader: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.isDarkAppearance) private var isDark
    let listing: ExtensionListing
    let isInstalled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            HStack(alignment: .top, spacing: metrics.spacing.md) {
                ExtensionIconView(
                    resolved: listing.iconURL(isDark: isDark).map {
                        ExtensionImage.Resolved(source: .remote($0))
                    },
                    size: metrics.size.rowIcon * 2)
                VStack(alignment: .leading, spacing: metrics.spacing.xxs) {
                    Text(listing.title)
                        .font(metrics.typography.panelTitle)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(listing.subtitle)
                        .font(metrics.typography.keyCap)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !listing.summary.isEmpty {
                Text(listing.summary)
                    .font(metrics.typography.rowTitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !tags.isEmpty {
                FlowLayout(spacing: metrics.spacing.xs) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(metrics.typography.compactKeyCap)
                            .padding(.horizontal, metrics.spacing.sm)
                            .padding(.vertical, metrics.spacing.xxs)
                            .background(ExtensionColors.detailCardFill, in: .capsule)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var tags: [String] {
        var tags = listing.categories
        tags.append(listing.registryName)
        if isInstalled { tags.append("Installed") }
        return tags
    }
}
