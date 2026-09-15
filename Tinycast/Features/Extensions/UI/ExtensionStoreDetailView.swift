import SwiftUI

/// The store page, restated: header, screenshots, then the blurb and commands beside the facts.
struct ExtensionStoreDetailView: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.isDarkAppearance) private var isDark
    @Environment(PaletteState.self) private var palette
    let listing: ExtensionListing
    let detail: ExtensionStoreDetail?
    let failure: String?
    let installState: ExtensionStoreSession.InstallState
    let selectedScreenshot: Int?
    let onSelectScreenshot: (Int) -> Void
    let onOpenLink: (URL) -> Void
    let onViewDeveloper: () -> Void
    /// The search field is hidden here, so the page itself holds focus for the palette's keys.
    @FocusState private var focused: Bool

    private var heroIconSide: CGFloat { metrics.scaled(64) }
    private var avatarSide: CGFloat { metrics.scaled(18) }
    private var screenshotHeight: CGFloat { metrics.scaled(140) }
    private var factsWidth: CGFloat { metrics.scaled(210) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.spacing.xxl) {
                header
                if let detail, !detail.screenshotURLs.isEmpty {
                    screenshots(detail.screenshotURLs)
                }
                HStack(alignment: .top, spacing: metrics.spacing.xxl) {
                    VStack(alignment: .leading, spacing: metrics.spacing.xxl) {
                        section("Description") {
                            Text(detail?.summary ?? listing.summary)
                                .font(metrics.typography.rowTitle)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let detail, !detail.commands.isEmpty {
                            section("Commands") { commands(detail.commands) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    facts
                        .frame(width: factsWidth, alignment: .leading)
                }
                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .font(metrics.typography.rowTrailing)
                        .foregroundStyle(.orange)
                }
                if case .failed(let message) = installState {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(metrics.typography.rowTrailing)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, metrics.spacing.xxl)
            .padding(.vertical, metrics.spacing.md)
            .hideNativeScrollers()
        }
        .edgeDissolve()
        .thinScrollbar()
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onChange(of: palette.focusToken) { focused = true }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: metrics.spacing.xl) {
            ExtensionIconView(
                resolved: listing.iconURL(isDark: isDark).map {
                    ExtensionImage.Resolved(source: .remote($0))
                },
                size: heroIconSide)
            VStack(alignment: .leading, spacing: metrics.spacing.sm) {
                Text(detail?.title ?? listing.title)
                    .font(metrics.typography.markdownHeading1)
                    .lineLimit(1)
                HStack(spacing: metrics.spacing.lg) {
                    if let author = detail?.author {
                        Button(action: onViewDeveloper) {
                            HStack(spacing: metrics.spacing.xs) {
                                ExtensionStoreAvatar(person: author, size: avatarSide)
                                Text(author.name)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("View developer")
                    } else if !listing.author.isEmpty {
                        Label(listing.author, systemImage: "person")
                    }
                    if let count = detail?.downloadCount ?? listing.downloadCount, count > 0 {
                        Label(
                            "\(count.formatted(.number)) Installs", systemImage: "arrow.down.circle"
                        )
                        .monospacedDigit()
                    }
                    if detail?.hasAITools ?? listing.hasAITools {
                        Label("AI Extension", systemImage: "sparkles")
                            .help("Also ships AI tools, which Tinycast doesn't run")
                    }
                    if listing.needsBuild {
                        Label("Builds on install", systemImage: "hammer")
                    }
                }
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Screenshots

    private func screenshots(_ urls: [URL]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: metrics.spacing.lg) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                        ExtensionStoreRemoteImage(url: url)
                            .frame(width: screenshotHeight * 16 / 10, height: screenshotHeight)
                            .overlay(
                                RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                                    .strokeBorder(
                                        index == selectedScreenshot
                                            ? Theme.Colors.border : Theme.Colors.cardStroke,
                                        lineWidth: index == selectedScreenshot ? 2 : 1)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { onSelectScreenshot(index) }
                            .id(index)
                            .accessibilityLabel("Screenshot \(index + 1)")
                            .accessibilityAddTraits(.isButton)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)
            .onChange(of: selectedScreenshot, initial: true) {
                guard let selectedScreenshot else { return }
                withAnimation { proxy.scrollTo(selectedScreenshot) }
            }
        }
    }

    // MARK: - Commands

    private func commands(_ commands: [ExtensionStoreDetail.Command]) -> some View {
        VStack(alignment: .leading, spacing: metrics.spacing.lg) {
            ForEach(commands) { command in
                VStack(alignment: .leading, spacing: metrics.spacing.xs) {
                    HStack(spacing: metrics.spacing.sm) {
                        ExtensionIconView(
                            resolved: (command.iconURL(isDark: isDark) ?? listing.iconURL(isDark: isDark))
                                .map { ExtensionImage.Resolved(source: .remote($0)) },
                            size: metrics.scaled(18))
                        Text(command.title)
                            .font(metrics.typography.rowTitle.weight(.medium))
                    }
                    if !command.description.isEmpty {
                        Text(command.description)
                            .font(metrics.typography.rowTrailing)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .textSelection(.enabled)
    }

    // MARK: - Facts

    @ViewBuilder
    private var facts: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xxl) {
            if let detail {
                if let readme = detail.readmeURL {
                    section("README") { link("Open README", to: readme) }
                }
                if let updated = detail.updatedAt {
                    section("Last update") {
                        Text(updated.formatted(date: .abbreviated, time: .shortened))
                            .font(metrics.typography.rowTitle)
                    }
                }
                if !detail.categories.isEmpty {
                    section("Categories") { tags(detail.categories) }
                }
                if !detail.contributors.isEmpty {
                    section("Contributors") { contributors(detail.contributors) }
                }
                if let source = detail.sourceURL {
                    section("Source") { link("View on GitHub", to: source) }
                }
            } else if failure == nil, listing.registryID == ExtensionRegistry.store.id {
                ProgressView().controlSize(.small)
            } else {
                section("Registry") {
                    Text(listing.registryName).font(metrics.typography.rowTitle)
                }
                if !listing.categories.isEmpty {
                    section("Categories") { tags(listing.categories) }
                }
                if let page = listing.storeURL {
                    section("Source") { link("View on GitHub", to: page) }
                }
            }
        }
    }

    private func link(_ title: String, to url: URL) -> some View {
        Button(action: { onOpenLink(url) }) {
            HStack(spacing: metrics.spacing.xs) {
                Text(title)
                Image(systemName: "arrow.up.right")
                    .font(metrics.typography.disclosure)
            }
            .font(metrics.typography.rowTitle)
        }
        .buttonStyle(.plain)
        .help(url.absoluteString)
    }

    private func tags(_ categories: [String]) -> some View {
        FlowLayout(spacing: metrics.spacing.xs) {
            ForEach(categories, id: \.self) { category in
                Text(category)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, metrics.spacing.sm)
                    .padding(.vertical, metrics.spacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: metrics.radius.menu, style: .continuous)
                            .fill(Theme.Colors.controlSurface))
            }
        }
    }

    private func contributors(_ people: [ExtensionStoreDetail.Person]) -> some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            ForEach(people) { person in
                HStack(spacing: metrics.spacing.sm) {
                    ExtensionStoreAvatar(person: person, size: avatarSide)
                    Text(person.name)
                        .font(metrics.typography.rowTitle)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture { if let url = person.profileURL { onOpenLink(url) } }
            }
        }
    }

    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xs) {
            Text(title)
                .font(metrics.typography.sectionHeader)
                .foregroundStyle(.secondary)
            content()
        }
    }
}
