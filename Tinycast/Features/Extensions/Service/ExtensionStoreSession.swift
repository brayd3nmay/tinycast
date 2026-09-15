import Foundation

/// The Store screen's transient state: one debounced search, the selection's README, and installs.
@MainActor
@Observable
final class ExtensionStoreSession {
    enum State: Equatable {
        case idle
        case searching
        case ready
    }

    /// What the row's trailing edge says; `installed` is this session's own doing, not the scan's.
    enum InstallState: Equatable {
        case installing(String)
        case installed
        case failed(String)
    }

    enum ReadmeState: Equatable {
        case loading
        case text(String)
        case unavailable
    }

    private(set) var results: [ExtensionListing] = []
    /// A registry that failed, named: its rows are missing and the list looks merely short.
    private(set) var notices: [String] = []
    private(set) var state: State = .idle
    private(set) var installs: [String: InstallState] = [:]
    private(set) var readmes: [String: ReadmeState] = [:]

    /// Built on first search: a store nobody opens should cost launch nothing at all.
    @ObservationIgnored private lazy var client = ExtensionStoreClient()
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    /// The published query, so re-entering the screen with the same text doesn't re-spend a call.
    @ObservationIgnored private var query: String?

    /// Long enough to swallow a burst of typing, on a registry limit of sixty calls an hour.
    private static let debounce = Duration.milliseconds(350)

    // MARK: - Searching

    /// Every keystroke is a request to someone else's API, on a limit of sixty an hour.
    func search(_ rawQuery: String, in registries: [ExtensionRegistry]) {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchTask?.cancel()
            searchTask = nil
            query = nil
            results = []
            notices = []
            state = .idle
            return
        }
        guard trimmed != query || state == .idle else { return }
        searchTask?.cancel()
        query = trimmed
        state = .searching
        searchTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            await run(trimmed, in: registries)
        }
    }

    /// Leaving the screen: nothing here outlives the visit, and a pending call has no reader.
    func reset() {
        searchTask?.cancel()
        searchTask = nil
        query = nil
        results = []
        notices = []
        readmes = [:]
        installs = [:]
        state = .idle
    }

    private func run(_ trimmed: String, in registries: [ExtensionRegistry]) async {
        let found = await client.search(trimmed, in: registries)
        guard !Task.isCancelled, query == trimmed else { return }
        // The store's copy wins a tie: it is prebuilt, so installing it needs no toolchain.
        var seen = Set<String>()
        var merged: [ExtensionListing] = []
        for result in found {
            for listing in result.listings where seen.insert(listing.name).inserted {
                merged.append(listing)
            }
        }
        results = merged
        notices = found.compactMap { result in
            result.failure.map { "\(result.registry.name): \($0)" }
        }
        state = .ready
    }

    // MARK: - The preview

    func readme(for listing: ExtensionListing) -> ReadmeState? { readmes[listing.id] }

    /// Driven by the detail pane's `task(id:)`, so stepping past a row cancels its fetch.
    func loadReadme(for listing: ExtensionListing) async {
        guard readmes[listing.id] == nil else { return }
        guard let url = listing.readmeURL else {
            readmes[listing.id] = .unavailable
            return
        }
        // Arrowing through the list would otherwise fetch a README per row passed over.
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        readmes[listing.id] = .loading
        guard let data = try? await client.download(url), let text = ExtensionReadme.decoded(data)
        else {
            readmes[listing.id] = .unavailable
            return
        }
        readmes[listing.id] = .text(
            ExtensionReadme.absoluteImages(in: text, base: ExtensionReadme.assetsBase(forRaw: url)))
    }

    // MARK: - Installing

    func installState(for listing: ExtensionListing) -> InstallState? { installs[listing.id] }

    func setInstallState(_ state: InstallState?, for listing: ExtensionListing) {
        installs[listing.id] = state
    }
}
