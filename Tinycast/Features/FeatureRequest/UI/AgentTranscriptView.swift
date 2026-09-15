import SwiftUI

/// The conversation with the agent that built one request.
///
/// Deliberately duplicated from `ChatTranscriptView` rather than shared, and deliberately smaller:
/// the agent sends no images, no documents and runs no web searches, so none of that is carried.
/// See docs/features/feature-request.md#why-the-transcript-is-duplicated.
struct AgentTranscriptView: View {
    @Environment(\.metrics) private var metrics
    let messages: [AgentMessage]
    let status: String?
    /// Cleared when the reader scrolls up, so a streaming reply stops dragging them back down.
    @State private var followsTail = true

    /// Below this a backward move is momentum settling, not the reader asking for the wheel.
    private static let deliberateScroll: CGFloat = 2
    private static let tailAnchor = "agent-transcript-tail"

    /// Where the reader sits and whether that is the end; a growing reply moves the end on its own.
    private struct ScrollMark: Equatable {
        var offset: CGFloat
        var atEnd: Bool
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Not lazy: every anchored jump and the end test measure an estimated height.
                VStack(spacing: metrics.spacing.xl) {
                    ForEach(messages) { message in
                        AgentMessageView(
                            message: message,
                            status: message.id == messages.last?.id ? status : nil
                        )
                        .id(message.id)
                    }
                    Color.clear
                        .frame(height: metrics.spacing.xxs)
                        .id(Self.tailAnchor)
                }
                .padding(.horizontal, metrics.spacing.xxl)
                .padding(.top, metrics.spacing.xl)
                .padding(.bottom, metrics.spacing.chatTranscriptBottom)
            }
            .edgeDissolve()
            .thinScrollbar()
            // Reopened conversations start at the latest message; other anchors fight the reader.
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .onScrollGeometryChange(for: ScrollMark.self) { geometry in
                ScrollMark(
                    offset: geometry.contentOffset.y,
                    atEnd: geometry.contentOffset.y + geometry.containerSize.height
                        + geometry.contentInsets.top
                        >= geometry.contentSize.height - metrics.spacing.chatFollowTailSlack)
            } action: { old, new in
                // The offset is the only signal every device gives; the end wins, tested first.
                if new.atEnd {
                    followsTail = true
                } else if new.offset < old.offset - Self.deliberateScroll {
                    followsTail = false
                }
            }
            .onChange(of: messages.count) { follow(proxy, always: true) }
            .onChange(of: messages) { follow(proxy, always: false) }
            .overlay(alignment: .bottom) {
                ResumeFollowingButton {
                    followsTail = true
                    follow(proxy, always: true)
                }
                .padding(.bottom, metrics.spacing.lg)
                .opacity(followsTail ? 0 : 1)
                .allowsHitTesting(!followsTail)
                .animation(.easeOut(duration: Theme.Duration.chatFooter), value: followsTail)
            }
        }
    }

    /// A sent message always comes into view; a growing reply only while the reader is at the end.
    private func follow(_ proxy: ScrollViewProxy, always: Bool) {
        guard always || followsTail else { return }
        proxy.scrollTo(Self.tailAnchor, anchor: .bottom)
    }
}

/// A fast reply outruns a reader scrolling toward it, so this asks for the tail, not chases it.
private struct ResumeFollowingButton: View {
    @Environment(\.metrics) private var metrics
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Jump to Latest", systemImage: "arrow.down")
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.horizontal, metrics.spacing.lg)
                .padding(.vertical, metrics.spacing.sm)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.Colors.border))
        }
        .buttonStyle(.plain)
    }
}

private struct AgentMessageView: View {
    @Environment(\.metrics) private var metrics
    let message: AgentMessage
    let status: String?

    @State private var hovered = false

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: metrics.spacing.xxl) }
            VStack(
                alignment: message.role == .user ? .trailing : .leading,
                spacing: metrics.spacing.xxs
            ) {
                content
                if message.state != .streaming { footer }
            }
            .contentShape(Rectangle())
            .onHover { isHovered in
                if isHovered {
                    withAnimation(.easeOut(duration: Theme.Duration.chatFooter)) { hovered = true }
                } else {
                    hovered = false
                }
            }
            if message.role == .agent { Spacer(minLength: metrics.spacing.xxl) }
        }
    }

    /// Laid out at rest and only faded in, so a hover cannot reflow the transcript.
    private var footer: some View {
        HStack(spacing: metrics.spacing.sm) {
            if message.role == .user { timestamp }
            AgentCopyButton(text: message.text)
            if message.role == .agent { timestamp }
        }
        .opacity(hovered ? 1 : 0)
        .padding(.horizontal, message.role == .user ? metrics.spacing.md : metrics.spacing.sm)
    }

    private var timestamp: some View {
        Text(message.sentAt.formatted(date: .omitted, time: .shortened))
            .font(metrics.typography.keyCap)
            .foregroundStyle(Theme.Colors.textTertiary)
    }

    @ViewBuilder private var content: some View {
        if message.text.isEmpty, message.toolCalls.isEmpty, message.state == .streaming {
            HStack(spacing: metrics.spacing.sm) {
                ProgressView().controlSize(.small)
                if let status { Text(status).foregroundStyle(.secondary) }
            }
            .padding(metrics.spacing.md)
        } else {
            rendered
                .font(metrics.typography.rowTitle)
                .foregroundStyle(message.state == .failed ? Theme.Colors.destructive : .primary)
                .textSelection(.enabled)
                // The user bubble is inset because it carries a fill; a reply clears the chevron.
                .padding(
                    .horizontal, message.role == .user ? metrics.spacing.xl : metrics.spacing.sm
                )
                .padding(.vertical, metrics.spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                        .fill(message.role == .user ? Theme.Colors.controlSurface : Color.clear)
                )
        }
    }

    /// Only a reply is markdown — what the user typed is shown back exactly as they typed it.
    @ViewBuilder private var rendered: some View {
        if message.role == .agent {
            VStack(alignment: .leading, spacing: metrics.spacing.lg) {
                ForEach(Array(message.segments.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .text(let text):
                        AgentMarkdownView(blocks: AgentMarkdownBlock.parse(text))
                    case .tool(let call):
                        AgentToolRow(call: call)
                    }
                }
            }
        } else {
            VStack(alignment: .trailing, spacing: metrics.spacing.xxs) {
                Text(message.text)
                // A change is the only turn that writes, so it says so where it was asked for.
                if message.intent == .change {
                    Label("Change", systemImage: "arrow.triangle.branch")
                        .font(metrics.typography.keyCap)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
        }
    }
}

private struct AgentToolRow: View {
    @Environment(\.metrics) private var metrics
    let call: AgentToolCall

    var body: some View {
        HStack(spacing: metrics.spacing.sm) {
            if call.isRunning {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "wrench.and.screwdriver")
                    .font(metrics.typography.rowTrailing)
                    .symbolRenderingMode(.hierarchical)
            }
            Text(call.label)
                .font(metrics.typography.rowTrailing)
                .lineLimit(1)
        }
        .foregroundStyle(Theme.Colors.textSecondary)
        .animation(.easeOut(duration: Theme.Duration.chatFooter), value: call.isRunning)
    }
}
