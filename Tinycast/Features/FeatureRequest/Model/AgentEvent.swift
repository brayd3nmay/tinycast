import Foundation

/// A line of the coding agent's stream, reduced to the only three things the pipeline acts on.
enum AgentEvent: Sendable, Equatable {
    /// Carries the session the next attempt resumes, so a retry keeps what the first one learned.
    case started(sessionID: String)
    case narration(String)
    case activity(String)
    case finished(Result)

    struct Result: Sendable, Equatable {
        let isError: Bool
        let summary: String
        let turns: Int
        let sessionID: String?

        init(isError: Bool, summary: String, turns: Int = 0, sessionID: String? = nil) {
            self.isError = isError
            self.summary = summary
            self.turns = turns
            self.sessionID = sessionID
        }
    }

    /// The progress line a tool call earns. Its argument is the useful half — `Edit` alone is noise.
    static func summary(tool: String, input: [String: Any]) -> String {
        func text(_ key: String) -> String? {
            guard let value = input[key] as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let detail: String? =
            switch tool {
            case "Bash", "BashOutput": text("description") ?? text("command")
            case "Read", "Edit", "Write", "NotebookEdit": text("file_path").map(shorten)
            case "Glob", "Grep": text("pattern")
            case "Task", "Agent": text("description")
            case "WebFetch": text("url")
            case "WebSearch": text("query")
            case "TodoWrite": "Updating plan"
            default: nil
            }
        guard let detail else { return tool }
        return tool + " " + clip(detail.replacingOccurrences(of: "\n", with: " "))
    }

    /// Enough of a path to recognise the file without the repo prefix every path here shares.
    private static func shorten(_ path: String) -> String {
        let parts = path.split(separator: "/")
        return parts.suffix(2).joined(separator: "/")
    }

    private static func clip(_ text: String, limit: Int = 72) -> String {
        text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
    }

    /// The first sentence of the agent's prose; the rest is for the transcript, not a status row.
    static func narration(from text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let line else { return nil }
        return clip(line.trimmingCharacters(in: .whitespaces), limit: 120)
    }
}
