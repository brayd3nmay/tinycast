import AppKit

enum PaletteMode: String, CaseIterable, Identifiable {
    case launcher
    case clipboard
    case ai
    case aiHistory
    case calculatorHistory
    case emoji
    case fileSearch
    case menuSearch
    case switchWindows
    case schedule
    case uninstall
    case quicklinks
    case snippets
    case featureRequest
    case featureRequestChat
    /// Collects a custom command's positional arguments, held on its own session.
    case customCommandArguments
    /// A Raycast extension command rendering into the palette.
    case extensionCommand
    /// The extension store: every registry searched, the front page browsed.
    case extensionStore
    /// One store listing's page, pushed over the store's results.
    case extensionStoreDetail

    var id: String { rawValue }

    /// One value at a time into the search field, so ↵ still acts with no rows to select.
    var isArgumentForm: Bool { self == .customCommandArguments }
    var systemImage: String {
        switch self {
        case .launcher: return "magnifyingglass"
        case .clipboard: return "doc.on.doc"
        case .ai: return "sparkles"
        case .aiHistory: return "clock.arrow.circlepath"
        case .calculatorHistory: return "plus.forwardslash.minus"
        case .emoji: return "face.smiling"
        case .fileSearch: return "doc.text.magnifyingglass"
        case .menuSearch: return "menubar.rectangle"
        case .switchWindows: return "macwindow.on.rectangle"
        case .schedule: return "calendar"
        case .uninstall: return "trash"
        case .quicklinks: return Quicklink.sfSymbol
        case .customCommandArguments: return CustomCommand.sfSymbol
        case .snippets: return "curlybraces"
        case .featureRequest: return "hammer"
        case .featureRequestChat: return "bubble.left.and.text.bubble.right"
        case .extensionCommand: return "puzzlepiece.extension"
        case .extensionStore, .extensionStoreDetail: return "storefront"
        }
    }
    var placeholder: String {
        switch self {
        case .launcher: return "Search for apps and commands…"
        case .clipboard: return "Type to filter entries…"
        case .ai: return "Ask anything…"
        case .aiHistory: return "Search chats…"
        case .calculatorHistory: return "Do math, convert units, or search your past calculations…"
        case .emoji: return "Search emoji and symbols…"
        case .fileSearch: return "Search files and folders…"
        case .menuSearch: return "Search menu bar items…"
        case .switchWindows: return "Search open windows…"
        case .schedule: return "Search your schedule…"
        case .uninstall: return "Filter files and folders by name…"
        case .quicklinks: return "Search quicklinks…"
        case .snippets: return "Search snippets…"
        case .featureRequest: return "Describe the feature you want…"
        case .featureRequestChat: return "Ask about this feature…"
        // Replaced by the pending argument's name; only reached if the session vanished mid-render.
        case .customCommandArguments: return "Enter a value…"
        // Replaced by the command's own `searchBarPlaceholder` whenever it declares one.
        case .extensionCommand: return "Search…"
        case .extensionStore: return "Search Store for Extensions…"
        // Hidden: the page has no field, and the chevron alone heads it.
        case .extensionStoreDetail: return ""
        }
    }
}

/// The app a paste lands in, resolved once per show so nothing re-reads it per render.
struct PasteTarget: Equatable {
    let name: String
    /// Bundle path for `IconCache` — nil for a target with no on-disk bundle.
    let iconPath: String?

    init?(app: NSRunningApplication?) {
        guard let app, let name = app.localizedName else { return nil }
        self.name = name
        iconPath = app.bundleURL?.path
    }

    var pasteTitle: String { "Paste to \(name)" }
}
