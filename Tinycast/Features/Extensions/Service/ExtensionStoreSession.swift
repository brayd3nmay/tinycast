import Foundation

/// The store screen's state: what was searched, what came back, and what is being installed.
@MainActor
@Observable
final class ExtensionStoreSession {
    enum State: Equatable {
        case idle
        case loading
        case ready
    }

    /// One row's install status, read by the list and the detail alike.
    enum InstallState: Equatable {
        case idle
        case installing(String)
        case installed
        case alreadyInstalled
        case failed(String)
    }

    /// Every listing loaded for the current query, before the category sifts it.
    private(set) var listings: [ExtensionListing] = []
    private(set) var state: State = .idle
    /// A registry that failed is worth saying so about — the results are quietly incomplete.
    private(set) var notices: [String] = []
    var category: ExtensionStoreCategory = .all
    /// True while a further browse page is on its way, so the list can show it at the end.
    private(set) var isLoadingMore = false
    /// The listing the detail screen is showing, kept here so a re-summon lands on it again.
    private(set) var opened: ExtensionListing?
    private(set) var details: [ExtensionListing.ID: ExtensionStoreDetail] = [:]
    private(set) var detailFailures: [ExtensionListing.ID: String] = [:]
    /// The detail's screenshot overlay; the selected screenshot is the palette's selection.
    var isPreviewingScreenshot = false
    private(set) var installing: [ExtensionListing.ID: ExtensionInstaller.Progress] = [:]
    private(set) var failures: [ExtensionListing.ID: String] = [:]
    /// Installed from here this session, so a row keeps its checkmark after the manager refreshes.
    private(set) var installedNames: Set<String> = []

    @ObservationIgnored private var query = ""
    @ObservationIgnored private var registries: [ExtensionRegistry] = []
    /// The browse page fetched last; nil once the store ran out, or while searching.
    @ObservationIgnored private var nextBrowsePage: Int?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var detailTasks: [ExtensionListing.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private let client: ExtensionStoreClient
    @ObservationIgnored private let extensions: ExtensionManager

    /// Every keystroke is a request to someone else's API, so a burst coalesces into one.
    private static let debounce = Duration.milliseconds(350)
    /// The front page is ten a call; a category can sift most of those, so a few come at once.
    private static let browsePagesPerLoad = 3
    /// Popularity tails off fast, and every page past this costs a call for little.
    private static let browsePageLimit = 30

    init(extensions: ExtensionManager, client: ExtensionStoreClient = ExtensionStoreClient()) {
        self.extensions = extensions
        self.client = client
    }

    /// The rows the screen shows: the loaded listings, less the ones outside the category.
    var rows: [ExtensionListing] {
        listings.filter { category.matches($0.categories) }
    }

    var isBrowsing: Bool { query.isEmpty }

    var canLoadMore: Bool { isBrowsing && nextBrowsePage != nil }

    // MARK: - Searching

    /// An empty query browses the store's front page; anything else searches every registry.
    func search(_ rawQuery: String, in registries: [ExtensionRegistry]) {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespaces)
        guard trimmed != query || registries != self.registries || state == .idle else { return }
        query = trimmed
        self.registries = registries
        revision &+= 1
        let revision = revision
        searchTask?.cancel()
        state = .loading
        notices = []
        isLoadingMore = false
        nextBrowsePage = nil
        searchTask = Task { [weak self] in
            guard let self else { return }
            if trimmed.isEmpty {
                await browse(from: 1, replacing: true, revision: revision)
            } else {
                try? await Task.sleep(for: Self.debounce)
                guard !Task.isCancelled else { return }
                await run(trimmed, revision: revision)
            }
        }
    }

    /// The next few front-page calls; a no-op while one is under way or once the store is spent.
    func loadMore() {
        guard canLoadMore, !isLoadingMore, let page = nextBrowsePage else { return }
        isLoadingMore = true
        let revision = revision
        searchTask = Task { [weak self] in
            await self?.browse(from: page, replacing: false, revision: revision)
        }
    }

    private func browse(from page: Int, replacing: Bool, revision: Int) async {
        let storeEnabled = registries.contains { $0.kind == .raycastStore && $0.isEnabled }
        var loaded: [ExtensionListing] = []
        var next: Int? = page
        var failure: String?
        if storeEnabled {
            for offset in 0..<Self.browsePagesPerLoad {
                let current = page + offset
                guard current <= Self.browsePageLimit else {
                    next = nil
                    break
                }
                do {
                    let batch = try await client.browse(page: current)
                    loaded += batch
                    next = batch.isEmpty ? nil : current + 1
                    if batch.isEmpty { break }
                } catch {
                    failure = error.localizedDescription
                    break
                }
            }
        } else {
            next = nil
        }
        guard revision == self.revision else { return }
        var seen = Set((replacing ? [] : listings).map(\.name))
        let fresh = loaded.filter { seen.insert($0.name).inserted }
        listings = replacing ? fresh : listings + fresh
        nextBrowsePage = next
        isLoadingMore = false
        state = .ready
        if let failure {
            notices = ["\(ExtensionRegistry.store.name): \(failure)"]
        } else if !storeEnabled {
            notices = ["Turn on the Raycast Store registry to browse; searching still works."]
        }
        // A category can sift a whole batch away; keep going until a row shows or the store ends.
        if rows.isEmpty, canLoadMore { loadMore() }
    }

    private func run(_ trimmed: String, revision: Int) async {
        let found = await client.search(trimmed, in: registries)
        guard revision == self.revision else { return }
        // The store's copy wins a tie: it is prebuilt, so installing it needs no toolchain.
        var seen = Set<String>()
        var merged: [ExtensionListing] = []
        for result in found {
            for listing in result.listings where seen.insert(listing.name).inserted {
                merged.append(listing)
            }
        }
        listings = merged
        notices = found.compactMap { result in
            result.failure.map { "\(result.registry.name): \($0)" }
        }
        if registries.allSatisfy({ !$0.isEnabled }) {
            notices = ["No registries are enabled. Turn one on in Settings › Extensions."]
        }
        state = .ready
    }

    // MARK: - Details

    func open(_ listing: ExtensionListing) {
        opened = listing
        isPreviewingScreenshot = false
        loadDetail(listing)
    }

    func closeDetail() {
        opened = nil
        isPreviewingScreenshot = false
    }

    func detail(for listing: ExtensionListing) -> ExtensionStoreDetail? { details[listing.id] }

    func detailFailure(for listing: ExtensionListing) -> String? { detailFailures[listing.id] }

    /// Only the store has a page to read; a GitHub listing already shows all its manifest says.
    func loadDetail(_ listing: ExtensionListing) {
        guard details[listing.id] == nil, detailTasks[listing.id] == nil,
            listing.registryID == ExtensionRegistry.store.id
        else { return }
        detailFailures[listing.id] = nil
        detailTasks[listing.id] = Task { [weak self] in
            guard let self else { return }
            do {
                let detail = try await client.detail(for: listing)
                details[listing.id] = detail
            } catch {
                detailFailures[listing.id] = error.localizedDescription
            }
            detailTasks[listing.id] = nil
        }
    }

    // MARK: - Installing

    func installState(for listing: ExtensionListing) -> InstallState {
        if let progress = installing[listing.id] { return .installing(progress.message) }
        if installedNames.contains(listing.name) { return .installed }
        if let failure = failures[listing.id] { return .failed(failure) }
        if extensions.installed.contains(where: { $0.manifest.name == listing.name }) {
            return .alreadyInstalled
        }
        return .idle
    }

    /// Throws what the installer threw, so the caller can say so; the row shows it too.
    func install(
        _ listing: ExtensionListing, packageManager: ExtensionPackageManager,
        additionalSearchPaths: [String]
    ) async throws {
        guard installing[listing.id] == nil else { return }
        failures[listing.id] = nil
        installing[listing.id] = .downloading
        defer { installing[listing.id] = nil }
        do {
            try await extensions.install(
                listing: listing, packageManager: packageManager,
                additionalSearchPaths: additionalSearchPaths,
                onProgress: { [weak self] progress in
                    // A step reported after the install settled must not revive its spinner.
                    Task { @MainActor in
                        guard let self, self.installing[listing.id] != nil else { return }
                        self.installing[listing.id] = progress
                    }
                })
            installedNames.insert(listing.name)
        } catch {
            failures[listing.id] = error.localizedDescription
            throw error
        }
    }
}
