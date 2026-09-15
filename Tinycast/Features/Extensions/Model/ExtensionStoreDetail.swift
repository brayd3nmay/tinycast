import Foundation

/// What the store page says about one extension beyond its row: screenshots, commands, people.
struct ExtensionStoreDetail: Equatable, Sendable {
    struct Command: Equatable, Sendable, Identifiable {
        let id: String
        let title: String
        let description: String
        let lightIconURL: URL?
        let darkIconURL: URL?

        func iconURL(isDark: Bool) -> URL? {
            isDark ? (darkIconURL ?? lightIconURL) : (lightIconURL ?? darkIconURL)
        }
    }

    struct Person: Equatable, Sendable, Identifiable {
        let id: String
        let name: String
        let handle: String
        let avatarURL: URL?
        /// The store's fallback tile colour, as `#RRGGBB`, drawn behind the initials.
        let placeholderColorHex: String?
        let initials: String

        var profileURL: URL? {
            guard !handle.isEmpty else { return nil }
            return URL(string: "https://www.raycast.com/\(handle)")
        }
    }

    let name: String
    let title: String
    let summary: String
    let author: Person?
    let downloadCount: Int
    let categories: [String]
    let screenshotURLs: [URL]
    let commands: [Command]
    /// Everyone credited, the owner first and past contributors last.
    let contributors: [Person]
    let updatedAt: Date?
    let readmeURL: URL?
    let sourceURL: URL?
    let storeURL: URL?
    /// Ships AI tools, which Tinycast doesn't run; shown so nobody installs for them.
    let hasAITools: Bool
}
