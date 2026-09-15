import SwiftUI

/// Store results as palette rows: icon, title and blurb, then installs and the author.
struct ExtensionStoreList: View {
    @Environment(\.metrics) private var metrics
    let rows: [ExtensionListing]
    let selectedID: ExtensionListing.ID?
    let sectionTitle: String
    let notices: [String]
    let isLoadingMore: Bool
    let installState: (ExtensionListing) -> ExtensionStoreSession.InstallState
    let scroll: ScrollIntent
    let onSelect: (ExtensionListing) -> Void
    let onActivate: () -> Void
    let onActions: (ExtensionListing) -> Void
    let onReachEnd: () -> Void

    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == rows.first?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if !notices.isEmpty {
                        noticeRow
                    }
                    SectionHeader(title: sectionTitle, isFirst: notices.isEmpty)
                    ForEach(rows) { listing in
                        ExtensionStoreRow(
                            listing: listing, selected: listing.id == selectedID,
                            state: installState(listing)
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
                        // Scrolling the last row into view asks for the next batch.
                        .onAppear { if listing.id == rows.last?.id { onReachEnd() } }
                    }
                    if isLoadingMore {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, metrics.spacing.md)
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selectedID, atOrigin: firstRowSelected, proxy: proxy)
        }
    }

    /// A registry that failed is named rather than silently missing from the rows below.
    private var noticeRow: some View {
        Label(notices.joined(separator: " · "), systemImage: "exclamationmark.triangle")
            .font(metrics.typography.rowTrailing)
            .foregroundStyle(.orange)
            .lineLimit(2)
            .padding(.horizontal, metrics.spacing.md)
            .padding(.top, metrics.spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One result: what it is, how many have it, and who made it — the store's own row, restated.
private struct ExtensionStoreRow: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.isDarkAppearance) private var isDark
    let listing: ExtensionListing
    let selected: Bool
    let state: ExtensionStoreSession.InstallState
    @State private var hovered = false

    /// A row carries two lines, so its icon sits a step above the launcher's one-line size.
    private var iconSide: CGFloat { metrics.scaled(28) }
    private var avatarSide: CGFloat { metrics.scaled(16) }

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
                },
                size: iconSide)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: metrics.spacing.sm) {
                    Text(listing.title)
                        .font(metrics.typography.rowTitle)
                        .lineLimit(1)
                    if listing.needsBuild {
                        badge("builds on install")
                    }
                }
                Text(listing.summary.isEmpty ? listing.subtitle : listing.summary)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: metrics.spacing.lg)
            trailing
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill)
        )
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(listing.title)
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: metrics.spacing.lg) {
            switch state {
            case .installing(let message):
                HStack(spacing: metrics.spacing.sm) {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                    Text(message)
                }
            case .installed:
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Colors.success)
            case .alreadyInstalled:
                Label("Installed", systemImage: "checkmark.circle")
            case .failed:
                Label("Failed", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            case .idle:
                if listing.hasAITools {
                    Image(systemName: "sparkles")
                        .help("Also ships AI tools, which Tinycast doesn't run")
                }
                if let count = listing.downloadCount, count > 0 {
                    Label(ExtensionListing.abbreviate(count), systemImage: "arrow.down.circle")
                        .monospacedDigit()
                }
            }
            if let avatar = listing.authorAvatarURL {
                ExtensionStoreRemoteImage(url: avatar, shape: AnyShape(Circle()))
                    .frame(width: avatarSide, height: avatarSide)
                    .help(listing.author)
            }
        }
        .font(metrics.typography.rowTrailing)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(metrics.typography.rowTrailing)
            .foregroundStyle(.secondary)
            .padding(.horizontal, metrics.spacing.sm)
            .padding(.vertical, metrics.spacing.xxs)
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.menu, style: .continuous)
                    .fill(Theme.Colors.controlSurface))
    }
}
