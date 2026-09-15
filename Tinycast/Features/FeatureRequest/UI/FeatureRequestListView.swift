import SwiftUI

struct FeatureRequestList: View {
    @Environment(\.metrics) private var metrics
    let rows: [FeatureRequestScreen.Row]
    let selectedID: FeatureRequestScreen.Row.ID?
    let activity: [UUID: String]
    let scroll: ScrollIntent
    let onSelect: (FeatureRequestScreen.Row) -> Void
    let onActivate: () -> Void
    let onActions: (FeatureRequestScreen.Row) -> Void

    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == rows.first?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        FeatureRequestRow(
                            row: row, selected: row.id == selectedID, activity: activity
                        )
                        .selectionFrame(row.id == selectedID)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(row) }
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                onSelect(row)
                                onActivate()
                            }
                        )
                        .onRightClick { onActions(row) }
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
                scroll, row: selectedID, atOrigin: firstRowSelected, proxy: proxy)
        }
    }
}

private struct FeatureRequestRow: View {
    @Environment(\.metrics) private var metrics
    let row: FeatureRequestScreen.Row
    let selected: Bool
    let activity: [UUID: String]
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(metrics.typography.rowTitle)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(metrics.typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: metrics.spacing.lg)
            if case .request(let request) = row, request.status.isRunning {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill)
        )
        .armedHover($hovered)
    }

    private var icon: some View {
        RoundedRectangle(cornerRadius: metrics.radius.thumbnail, style: .continuous)
            .fill(Theme.Colors.controlSurface)
            .frame(width: metrics.size.rowIcon, height: metrics.size.rowIcon)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary))
    }

    private var symbol: String {
        switch row {
        case .submit: return "hammer"
        case .amend: return "arrow.triangle.branch"
        case .request(let request): return request.status.symbol
        }
    }

    private var title: String {
        switch row {
        case .submit(let prompt): return "Build “\(prompt)”"
        case .amend(let request, _): return "Change “\(request.title)”"
        case .request(let request): return request.title
        }
    }

    /// The live agent line while a run is going, and the settled status once it is not.
    private var detail: String? {
        switch row {
        case .submit: return "Builds it, then opens a pull request"
        case .amend(_, let change): return change
        case .request(let request):
            if let line = activity[request.id] { return line }
            return request.status.label
        }
    }
}
