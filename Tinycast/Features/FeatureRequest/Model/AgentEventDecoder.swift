import Foundation

/// Splits `claude --output-format stream-json` into events. Line-buffered: a read lands mid-object.
struct AgentEventDecoder {
    /// A single tool result can outrun any sane line; past this the stream is malformed, not slow.
    private static let maximumPendingBytes = 8 * 1_048_576

    private var pending = Data()

    mutating func push(_ data: Data) -> [AgentEvent] {
        pending.append(data)
        guard pending.count <= Self.maximumPendingBytes else {
            pending.removeAll()
            return []
        }
        var events: [AgentEvent] = []
        while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
            let line = pending[pending.startIndex..<newline]
            pending.removeSubrange(pending.startIndex...newline)
            events += Self.events(from: String(decoding: line, as: UTF8.self))
        }
        return events
    }

    /// The last line arrives without its newline when the process exits, so it is flushed by hand.
    mutating func finish() -> [AgentEvent] {
        defer { pending.removeAll() }
        guard !pending.isEmpty else { return [] }
        return Self.events(from: String(decoding: pending, as: UTF8.self))
    }

    /// One line in, zero or more events out — a non-JSON line is the CLI's own chatter, not a fault.
    static func events(from line: String) -> [AgentEvent] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.hasPrefix("{") else { return [] }
        guard
            let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))
                as? [String: Any]
        else { return [] }

        switch object["type"] as? String {
        case "system":
            guard object["subtype"] as? String == "init",
                let session = object["session_id"] as? String
            else { return [] }
            return [.started(sessionID: session)]
        case "assistant":
            let message = object["message"] as? [String: Any]
            return (message?["content"] as? [[String: Any]] ?? []).compactMap(event(forBlock:))
        case "result":
            return [.finished(result(from: object))]
        default:
            return []
        }
    }

    private static func event(forBlock block: [String: Any]) -> AgentEvent? {
        switch block["type"] as? String {
        case "text":
            guard let text = block["text"] as? String,
                let line = AgentEvent.narration(from: text)
            else { return nil }
            return .narration(line)
        case "tool_use":
            guard let name = block["name"] as? String else { return nil }
            let input = block["input"] as? [String: Any] ?? [:]
            return .activity(AgentEvent.summary(tool: name, input: input))
        default:
            return nil
        }
    }

    private static func result(from object: [String: Any]) -> AgentEvent.Result {
        let subtype = object["subtype"] as? String ?? "success"
        let isError = object["is_error"] as? Bool ?? (subtype != "success")
        let text = object["result"] as? String ?? ""
        return AgentEvent.Result(
            isError: isError,
            summary: summary(subtype: subtype, isError: isError, text: text),
            turns: object["num_turns"] as? Int ?? 0,
            sessionID: object["session_id"] as? String)
    }

    /// `error_max_turns` arrives with no prose at all, so the subtype has to stand in for one.
    private static func summary(subtype: String, isError: Bool, text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        guard isError else { return "Finished with no summary." }
        return switch subtype {
        case "error_max_turns": "The agent hit its turn limit before finishing."
        case "error_during_execution": "The agent stopped on an internal error."
        default: "The agent stopped early (\(subtype))."
        }
    }
}
