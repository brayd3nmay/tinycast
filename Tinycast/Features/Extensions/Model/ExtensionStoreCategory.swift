import Foundation

/// The store's own category names; the search endpoint has no filter, so rows are sifted here.
enum ExtensionStoreCategory: String, CaseIterable, Identifiable, Sendable {
    case all
    case applications = "Applications"
    case communication = "Communication"
    case data = "Data"
    case designTools = "Design Tools"
    case developerTools = "Developer Tools"
    case documentation = "Documentation"
    case finance = "Finance"
    case fun = "Fun"
    case media = "Media"
    case news = "News"
    case productivity = "Productivity"
    case security = "Security"
    case system = "System"
    case web = "Web"
    case webSearch = "Web Search"
    case other = "Other"
    case ai = "AI Extensions"

    var id: String { rawValue }

    var title: String { self == .all ? "All Categories" : rawValue }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .applications: return "app"
        case .communication: return "bubble.left.and.bubble.right"
        case .data: return "chart.bar"
        case .designTools: return "paintpalette"
        case .developerTools: return "hammer"
        case .documentation: return "book"
        case .finance: return "dollarsign.circle"
        case .fun: return "gamecontroller"
        case .media: return "play.rectangle"
        case .news: return "newspaper"
        case .productivity: return "checkmark.circle"
        case .security: return "lock"
        case .system: return "gearshape"
        case .web: return "globe"
        case .webSearch: return "magnifyingglass"
        case .other: return "ellipsis.circle"
        case .ai: return "sparkles"
        }
    }

    /// Case-insensitive: the store capitalises its names, a GitHub manifest need not.
    func matches(_ categories: [String]) -> Bool {
        guard self != .all else { return true }
        return categories.contains { $0.caseInsensitiveCompare(rawValue) == .orderedSame }
    }
}
