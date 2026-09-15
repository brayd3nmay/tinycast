import Foundation

/// The conversation held with one request's agent, kept beside the log rather than inside it.
///
/// A transcript is far larger than a request record, and only one is ever on screen, so it lives in
/// its own file and is loaded on demand — `featureRequests` in `UserDefaults` stays small.
@MainActor
@Observable
final class FeatureRequestChatStore {
    private(set) var messages: [AgentMessage] = []
    /// Which request `messages` belongs to; nothing is written back to the wrong transcript.
    private(set) var loaded: UUID?

    private let root: URL

    init(root: URL = AppPaths.applicationSupport().appending(path: "feature-request-chats")) {
        self.root = root
    }

    func load(_ request: FeatureRequest) {
        guard loaded != request.id else { return }
        loaded = request.id
        let data = try? Data(contentsOf: file(for: request.shortID))
        messages = data.flatMap { try? JSONDecoder().decode([AgentMessage].self, from: $0) } ?? []
    }

    func close() {
        loaded = nil
        messages = []
    }

    @discardableResult
    func append(_ message: AgentMessage) -> UUID {
        messages.append(message)
        persist()
        return message.id
    }

    func update(_ id: UUID, _ mutate: (inout AgentMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        mutate(&messages[index])
        persist()
    }

    /// A transcript outlives nothing: removing the request removes the conversation with it.
    func discard(_ shortID: String) {
        try? FileManager.default.removeItem(at: file(for: shortID))
    }

    /// Sweeps transcripts whose request has left the log, the way previews are swept.
    func sweep(keeping live: [String]) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        let kept = Set(live.map { $0 + ".json" })
        for name in names where name.hasSuffix(".json") && !kept.contains(name) {
            try? FileManager.default.removeItem(at: root.appending(path: name))
        }
    }

    private func file(for shortID: String) -> URL {
        root.appending(path: shortID + ".json")
    }

    private func persist() {
        guard let loaded, let request = shortID(for: loaded) else { return }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(messages) else { return }
        try? data.write(to: file(for: request), options: .atomic)
    }

    /// Derived the same way everywhere else, so a transcript file is findable from its request.
    private func shortID(for id: UUID) -> String? {
        id.uuidString.prefix(8).lowercased()
    }
}
