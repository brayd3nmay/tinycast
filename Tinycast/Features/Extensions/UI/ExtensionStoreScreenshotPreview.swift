import SwiftUI

/// One screenshot at panel size; the palette's ←/→ step it, and Escape hands back the page.
struct ExtensionStoreScreenshotPreview: View {
    @Environment(\.metrics) private var metrics
    let title: String
    let urls: [URL]
    let index: Int
    let onStep: (Int) -> Void
    let onClose: () -> Void

    /// Concentric: every corner inside the panel is the one outside it less its own inset.
    private var cardRadius: CGFloat { metrics.radius.panel - metrics.spacing.md }
    private var surfaceRadius: CGFloat { cardRadius - metrics.spacing.md }

    var body: some View {
        ZStack {
            // Only the margin dismisses: a tap over the image belongs to its own controls.
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
            card
        }
    }

    private var card: some View {
        VStack(spacing: metrics.spacing.md) {
            ExtensionStoreRemoteImage(
                url: urls[index],
                shape: AnyShape(RoundedRectangle(cornerRadius: surfaceRadius, style: .continuous))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: metrics.spacing.sm) {
                Text("\(title) · \(index + 1) of \(urls.count)")
                    .font(metrics.typography.rowTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: metrics.spacing.lg)
                if index > 0 {
                    step("Previous", cap: "←", delta: -1)
                }
                if index < urls.count - 1 {
                    step("Next", cap: "→", delta: 1)
                }
                BarButton(action: onClose) {
                    HStack(spacing: metrics.spacing.sm) {
                        Text("Close")
                            .font(metrics.typography.bar)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        KeyCapChip(text: "esc", style: .outline)
                    }
                }
            }
        }
        .padding(metrics.spacing.md)
        .frosted(in: RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        .padding(metrics.spacing.md)
        .accessibilityLabel("Screenshot \(index + 1) of \(urls.count) for \(title)")
    }

    private func step(_ label: String, cap: String, delta: Int) -> some View {
        BarButton(action: { onStep(delta) }) {
            HStack(spacing: metrics.spacing.sm) {
                Text(label)
                    .font(metrics.typography.bar)
                    .foregroundStyle(Theme.Colors.textSecondary)
                KeyCapChip(text: cap, style: .outline)
            }
        }
    }
}
