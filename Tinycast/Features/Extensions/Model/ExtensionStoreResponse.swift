import Foundation

/// Both are other people's endpoints, so every field an install doesn't need is optional.
enum ExtensionStoreResponse {

    // MARK: - Raycast's store

    /// A page of search results, at most this many; the endpoint's own default is ten.
    static let searchPageSize = 50

    /// The endpoint the store's own website searches with. Unofficial, hence the GitHub fallback.
    static func searchURL(query: String, page: Int) -> URL? {
        var components = URLComponents(string: "https://www.raycast.com/frontend_api/extensions/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(searchPageSize)),
            // Case-sensitive: any other spelling returns only extensions listing no platforms.
            URLQueryItem(name: "platform", value: "macOS")
        ]
        return components?.url
    }

    /// The store's front page: most installed first, ten a page, and `per_page` is ignored.
    static func browseURL(page: Int) -> URL? {
        var components = URLComponents(string: "https://www.raycast.com/frontend_api/extensions")
        components?.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "platform", value: "macOS")
        ]
        return components?.url
    }

    /// One extension in full — screenshots, contributors, commands — by its author's slug and name.
    static func detailURL(handle: String, name: String) -> URL? {
        guard !handle.isEmpty, !name.isEmpty,
            let escapedHandle = handle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let escapedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: "https://backend.raycast.com/api/v1/extensions/\(escapedHandle)/\(escapedName)")
    }

    private struct StorePayload: Decodable {
        let data: [StoreEntry]
    }

    /// The search row and the detail page share one shape; the detail just fills more of it.
    private struct StoreEntry: Decodable {
        let id: String
        let name: String
        let title: String?
        let description: String?
        let author: Author?
        let icons: Icons?
        let commands: [Command]?
        let tools: [Tool]?
        let categories: [String]?
        let downloadCount: Int?
        let downloadURL: String?
        let storeURL: String?
        let sourceURL: String?
        let readmeURL: String?
        let updatedAt: Double?
        let metadata: [String]?
        let contributors: [Author]?
        let pastContributors: [Author]?
        let status: String?

        struct Author: Decodable {
            let id: String?
            let name: String?
            let handle: String?
            let avatar: String?
            let initials: String?
            let avatarPlaceholderColor: String?

            enum CodingKeys: String, CodingKey {
                case id, name, handle, avatar, initials
                case avatarPlaceholderColor = "avatar_placeholder_color"
            }
        }
        struct Icons: Decodable {
            let light: String?
            let dark: String?
        }
        struct Command: Decodable {
            let name: String?
            let title: String?
            let description: String?
            let icons: Icons?
        }
        struct Tool: Decodable {
            let name: String?
        }

        enum CodingKeys: String, CodingKey {
            case id, name, title, description, author, icons, commands, tools, categories, status
            case metadata, contributors
            case downloadCount = "download_count"
            case downloadURL = "download_url"
            case storeURL = "store_url"
            case sourceURL = "source_url"
            case readmeURL = "readme_url"
            case updatedAt = "updated_at"
            case pastContributors = "past_contributors"
        }

        var hasAITools: Bool { !(tools ?? []).isEmpty }
    }

    /// An entry without a usable download is dropped, not listed as uninstallable.
    static func parseStore(_ data: Data, registry: ExtensionRegistry) throws -> [ExtensionListing] {
        let payload = try JSONDecoder().decode(StorePayload.self, from: data)
        return payload.data.compactMap { entry -> ExtensionListing? in
            // A de-listed extension is still returned by search; it can't be downloaded any more.
            guard entry.status == nil || entry.status == "active" else { return nil }
            guard let raw = entry.downloadURL, let url = URL(string: raw) else { return nil }
            return ExtensionListing(
                id: entry.id,
                name: entry.name,
                title: entry.title ?? entry.name,
                summary: entry.description ?? "",
                author: entry.author?.name ?? entry.author?.handle ?? "",
                authorHandle: entry.author?.handle ?? "",
                authorAvatarURL: entry.author?.avatar.flatMap(URL.init(string:)),
                lightIconURL: entry.icons?.light.flatMap(URL.init(string:)),
                darkIconURL: entry.icons?.dark.flatMap(URL.init(string:)),
                commandCount: entry.commands?.count ?? 0,
                downloadCount: entry.downloadCount,
                categories: entry.categories ?? [],
                storeURL: entry.storeURL.flatMap(URL.init(string:)),
                hasAITools: entry.hasAITools,
                registryID: registry.id,
                registryName: registry.name,
                source: .prebuiltZip(url))
        }
    }

    /// The detail page. Screenshots are the `metadata` images, in the order the store shows them.
    static func parseDetail(_ data: Data) throws -> ExtensionStoreDetail {
        let entry = try JSONDecoder().decode(StoreEntry.self, from: data)
        let author = entry.author.flatMap(person)
        // Credited once each: the author heads the list even when also listed as a contributor.
        var seen = Set<String>()
        var contributors: [ExtensionStoreDetail.Person] = []
        for candidate in [author].compactMap({ $0 })
            + (entry.contributors ?? []).compactMap(person)
            + (entry.pastContributors ?? []).compactMap(person)
        where seen.insert(candidate.id).inserted {
            contributors.append(candidate)
        }
        return ExtensionStoreDetail(
            name: entry.name,
            title: entry.title ?? entry.name,
            summary: entry.description ?? "",
            author: author,
            downloadCount: entry.downloadCount ?? 0,
            categories: entry.categories ?? [],
            screenshotURLs: (entry.metadata ?? []).compactMap(URL.init(string:)),
            commands: (entry.commands ?? []).compactMap { command in
                guard let name = command.name else { return nil }
                return ExtensionStoreDetail.Command(
                    id: name,
                    title: command.title ?? name,
                    description: command.description ?? "",
                    lightIconURL: command.icons?.light.flatMap(URL.init(string:)),
                    darkIconURL: command.icons?.dark.flatMap(URL.init(string:)))
            },
            contributors: contributors,
            updatedAt: entry.updatedAt.map { Date(timeIntervalSince1970: $0) },
            readmeURL: entry.readmeURL.flatMap(URL.init(string:)),
            sourceURL: entry.sourceURL.flatMap(URL.init(string:)),
            storeURL: entry.storeURL.flatMap(URL.init(string:)),
            hasAITools: entry.hasAITools)
    }

    private static func person(_ author: StoreEntry.Author) -> ExtensionStoreDetail.Person? {
        let handle = author.handle ?? ""
        let name = author.name?.isEmpty == false ? author.name! : handle
        guard !name.isEmpty else { return nil }
        return ExtensionStoreDetail.Person(
            id: author.id ?? (handle.isEmpty ? name : handle),
            name: name,
            handle: handle,
            avatarURL: author.avatar.flatMap(URL.init(string:)),
            placeholderColorHex: author.avatarPlaceholderColor,
            initials: author.initials ?? String(name.prefix(2)))
    }

    // MARK: - A GitHub registry

    static func treeURL(
        owner: String, repository: String, sha: String, recursive: Bool = false
    ) -> URL? {
        var components = URLComponents(
            string: "https://api.github.com/repos/\(owner)/\(repository)/git/trees/\(sha)")
        if recursive { components?.queryItems = [URLQueryItem(name: "recursive", value: "1")] }
        return components?.url
    }

    /// A Git tree: what a directory holds, by sha rather than by path.
    struct GitTree: Decodable, Sendable {
        let tree: [Entry]
        /// Set when GitHub gave up listing: what came back is a prefix, not the whole directory.
        let truncated: Bool?

        struct Entry: Decodable, Sendable {
            let path: String
            let type: String
            let sha: String
            let mode: String?

            var isDirectory: Bool { type == "tree" }
            var isFile: Bool { type == "blob" }
            var isExecutable: Bool { isFile && mode == "100755" }
        }

        func directorySHA(named name: String) -> String? {
            tree.first { $0.path == name && $0.isDirectory }?.sha
        }

        var directoryNames: [String] { tree.filter(\.isDirectory).map(\.path) }
    }

    /// A tree listing, or a thrown message when GitHub answered with an error instead.
    static func parseTree(_ data: Data) throws -> GitTree {
        if let tree = try? JSONDecoder().decode(GitTree.self, from: data) { return tree }
        struct Message: Decodable { let message: String }
        if let error = try? JSONDecoder().decode(Message.self, from: data) {
            throw ExtensionStoreError.registryRejected(error.message)
        }
        throw ExtensionStoreError.malformedResponse
    }

    /// The parts of `package.json` a listing shows, read from the repository.
    static func parseManifestSummary(
        _ data: Data, folder: String, registry: ExtensionRegistry
    ) -> ExtensionListing? {
        struct Manifest: Decodable {
            let name: String?
            let title: String?
            let description: String?
            let author: String?
            let icon: String?
            let categories: [String]?
            let commands: [Command]?
            let tools: [Command]?
            struct Command: Decodable { let name: String? }
        }
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
            let name = manifest.name ?? manifest.title
        else { return nil }
        // One artwork per manifest, so both appearances resolve to it.
        let manifestIcon = manifest.icon.flatMap {
            URL(
                string:
                    "https://raw.githubusercontent.com/\(registry.owner)/\(registry.repository)"
                    + "/\(registry.ref)/\(registry.path)/\(folder)/assets/\($0)")
        }
        return ExtensionListing(
            id: "\(registry.id.uuidString)/\(folder)",
            name: name,
            title: manifest.title ?? name,
            summary: manifest.description ?? "",
            author: manifest.author ?? "",
            authorHandle: "",
            authorAvatarURL: nil,
            lightIconURL: manifestIcon,
            darkIconURL: manifestIcon,
            commandCount: manifest.commands?.count ?? 0,
            downloadCount: nil,
            categories: manifest.categories ?? [],
            storeURL: URL(
                string:
                    "https://github.com/\(registry.owner)/\(registry.repository)"
                    + "/tree/\(registry.ref)/\(registry.path)/\(folder)"),
            hasAITools: !(manifest.tools ?? []).isEmpty,
            registryID: registry.id,
            registryName: registry.name,
            source: .githubFolder(
                owner: registry.owner, repository: registry.repository,
                path: "\(registry.path)/\(folder)", ref: registry.ref))
    }
}

enum ExtensionStoreError: LocalizedError {
    case malformedResponse
    case registryRejected(String)
    case downloadFailed(String)
    case noPackageManager
    case noNode
    case buildFailed(String)
    case notAnExtension

    var errorDescription: String? {
        switch self {
        case .malformedResponse:
            return "The registry answered with something this version doesn't understand."
        case .registryRejected(let message):
            return message
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .noPackageManager:
            return
                "This extension is source that has to be built, and no package manager was found. "
                + "Install pnpm, npm, Yarn or Bun, or pick one in Advanced."
        case .noNode:
            return
                "This extension is source that has to be built, and Node wasn't found. Install "
                + "Node.js, or install this extension from the Raycast Store instead."
        case .buildFailed(let output):
            return "The extension didn't build: \(output)"
        case .notAnExtension:
            return "That download didn't contain a Raycast extension."
        }
    }
}
