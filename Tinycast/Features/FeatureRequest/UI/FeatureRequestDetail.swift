import SwiftUI

/// The right-hand pane: the request as written, and what each attempt made of it.
struct FeatureRequestDetail: View {
    @Environment(\.metrics) private var metrics
    let row: FeatureRequestScreen.Row?
    let activity: [UUID: String]

    var body: some View {
        switch row {
        case .submit(let prompt):
            pane { draft(prompt) }
        case .amend(let request, let change):
            pane { amendment(request, change: change) }
        case .request(let request):
            pane { detail(request) }
        case nil:
            Color.clear
        }
    }

    private func pane(@ViewBuilder _ content: () -> some View) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.spacing.lg) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.vertical, metrics.spacing.md)
        }
        .padding(.horizontal, 12)
        .edgeDissolve()
        .thinScrollbar()
    }

    @ViewBuilder
    private func draft(_ prompt: String) -> some View {
        section("Request") {
            Text(prompt).font(.system(.subheadline, design: .monospaced))
        }
        section("What happens next") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Self.steps, id: \.self) { step in
                    Text(step).font(metrics.typography.rowTrailing)
                }
            }
        }
    }

    /// Three lines that each fit on one: this is re-read on every keystroke, so it cannot be prose.
    private static let steps = [
        "Builds it in a scratch copy of your repo",
        "Runs the checks, retrying if they fail",
        "Opens a pull request once they pass"
    ]

    @ViewBuilder
    private func amendment(_ request: FeatureRequest, change: String) -> some View {
        section("Change") {
            Text(change).font(.system(.subheadline, design: .monospaced))
        }
        section("Applies to") {
            VStack(alignment: .leading, spacing: 4) {
                Text(request.title).font(metrics.typography.rowTitle).lineLimit(2)
                Text(request.branch)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        section("What happens next") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Self.amendSteps, id: \.self) { step in
                    Text(step).font(metrics.typography.rowTrailing)
                }
            }
        }
    }

    /// Named apart from `steps`: a change lands on the branch that exists, and opens nothing new.
    private static let amendSteps = [
        "Picks up where the agent left off, on the same branch",
        "Runs the checks again, retrying if they fail",
        "Updates the pull request that is already open"
    ]

    @ViewBuilder
    private func detail(_ request: FeatureRequest) -> some View {
        section("Request") {
            Text(request.prompt).font(.system(.subheadline, design: .monospaced))
        }
        section("Status") {
            VStack(alignment: .leading, spacing: 4) {
                Text(request.status.label).font(metrics.typography.rowTitle)
                if let line = activity[request.id] {
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                Text(request.branch)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .textSelection(.enabled)
            }
        }
        if !request.followUps.isEmpty {
            section("Changes asked for") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(request.followUps.enumerated()), id: \.offset) { _, change in
                        Text(change).font(.system(.subheadline, design: .monospaced))
                    }
                }
            }
        }
        ForEach(request.attempts) { attempt in
            section("Attempt \(attempt.id)") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(attempt.changedFiles) file\(attempt.changedFiles == 1 ? "" : "s") changed")
                        .font(metrics.typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.textTertiary)
                    ForEach(attempt.report?.summaryLines ?? [], id: \.self) { line in
                        Text(line).font(.system(.caption, design: .monospaced))
                    }
                    if let digest = attempt.report?.failure?.digest, !digest.isEmpty {
                        Text(digest)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xs) {
            Text(title.uppercased())
                .font(metrics.typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textTertiary)
            content()
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .textSelection(.enabled)
        }
    }
}
