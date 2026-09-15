import Foundation

/// The request log, newest first. Persisted so a finished run's pull request outlives the palette.
@MainActor
@Observable
final class FeatureRequestStore {
    private static let defaultsKey = "featureRequests"
    /// Enough to answer "what did I ask for last month"; a log is not an archive.
    private static let historyLimit = 40

    private let defaults: UserDefaults
    private(set) var requests: [FeatureRequest]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoded =
            defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([FeatureRequest].self, from: $0) } ?? []
        requests = Self.settled(decoded)
        if requests != decoded { persist() }
    }

    /// A run cannot survive the process that spawned it, so anything mid-flight died with the app.
    private static func settled(_ requests: [FeatureRequest]) -> [FeatureRequest] {
        requests.map { request in
            guard !request.status.isFinished else { return request }
            var settled = request
            settled.status = .failed(reason: "Interrupted when Tinycast quit.")
            return settled
        }
    }

    var active: FeatureRequest? { requests.first { $0.status.isRunning } }

    var queued: [FeatureRequest] { requests.filter { $0.status == .queued } }

    func request(id: UUID) -> FeatureRequest? { requests.first { $0.id == id } }

    func add(_ request: FeatureRequest) {
        requests.insert(request, at: 0)
        trim()
        persist()
    }

    func update(id: UUID, _ mutate: (inout FeatureRequest) -> Void) {
        guard let index = requests.firstIndex(where: { $0.id == id }) else { return }
        mutate(&requests[index])
        persist()
    }

    func remove(id: UUID) {
        requests.removeAll { $0.id == id }
        persist()
    }

    func clearFinished() {
        requests.removeAll { $0.status.isFinished }
        persist()
    }

    /// Drops the oldest finished rows only — a queued request must never fall off the end.
    private func trim() {
        guard requests.count > Self.historyLimit else { return }
        var kept = requests
        while kept.count > Self.historyLimit,
            let index = kept.lastIndex(where: { $0.status.isFinished })
        {
            kept.remove(at: index)
        }
        requests = kept
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(requests) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
