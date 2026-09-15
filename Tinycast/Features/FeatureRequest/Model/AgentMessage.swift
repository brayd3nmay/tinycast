import Foundation

/// One turn of the conversation with the agent that built a request. Persisted per request.
struct AgentMessage: Identifiable, Equatable, Sendable, Codable {
    enum Role: String, Equatable, Sendable, Codable {
        case user
        case agent
    }

    enum State: String, Equatable, Sendable, Codable {
        case streaming
        case complete
        case failed
    }

    /// What the turn was for; a question may never write, so the two can never be confused.
    enum Intent: String, Equatable, Sendable, Codable {
        case question
        case change
    }

    let id: UUID
    let role: Role
    var text: String
    var state: State
    let intent: Intent
    let sentAt: Date
    /// Tools the reply called, each pinned to where in the text it happened.
    var toolCalls: [AgentToolCall]

    init(
        id: UUID = UUID(), role: Role, text: String, state: State = .complete,
        intent: Intent = .question, sentAt: Date = Date(), toolCalls: [AgentToolCall] = []
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.state = state
        self.intent = intent
        self.sentAt = sentAt
        self.toolCalls = toolCalls
    }

    var isStreaming: Bool { state == .streaming }

    /// The reply split around what it did: text, tool call, text… rendered where it happened.
    var segments: [Segment] {
        var segments: [Segment] = []
        var rest = Substring(text)
        var consumed = 0
        for call in toolCalls.sorted(by: { $0.textOffset < $1.textOffset }) {
            let take = max(0, min(call.textOffset - consumed, rest.count))
            if take > 0 { segments.append(.text(String(rest.prefix(take)))) }
            segments.append(.tool(call))
            rest = rest.dropFirst(take)
            consumed += take
        }
        if !rest.isEmpty { segments.append(.text(String(rest))) }
        return segments
    }

    enum Segment: Equatable {
        case text(String)
        case tool(AgentToolCall)
    }
}

/// One tool call the agent made while answering, shown inline where it happened.
struct AgentToolCall: Identifiable, Equatable, Sendable, Codable {
    let id: UUID
    let label: String
    var isRunning: Bool
    /// Characters of reply text that had arrived when the call started, so it keeps its place.
    let textOffset: Int

    init(id: UUID = UUID(), label: String, isRunning: Bool = true, textOffset: Int) {
        self.id = id
        self.label = label
        self.isRunning = isRunning
        self.textOffset = textOffset
    }
}
