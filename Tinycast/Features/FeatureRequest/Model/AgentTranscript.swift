import Foundation

/// Which streaming message an in-flight answer is being written into, and which answer that is.
///
/// A value rather than stored state: an interrupted turn's events keep arriving for a moment, and
/// `token` is what stops them landing in the answer that replaced it.
struct AgentTranscript: Sendable {
    let messageID: UUID
    let token: UUID
}
