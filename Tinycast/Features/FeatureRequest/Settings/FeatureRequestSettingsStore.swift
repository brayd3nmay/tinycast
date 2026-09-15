import Foundation

/// Where the agent works and how hard it tries. Kept off `AppSettings`: none of it rides a backup.
@MainActor
@Observable
final class FeatureRequestSettingsStore {
    private enum Key: String {
        case repositoryPath = "featureRequestRepositoryPath"
        case baseBranch = "featureRequestBaseBranch"
        case model = "featureRequestModel"
        case maxAttempts = "featureRequestMaxAttempts"
        case maxTurns = "featureRequestMaxTurns"
        case opensPullRequest = "featureRequestOpensPullRequest"
    }

    static let attemptRange = 1...5
    static let turnRange = 20...400
    static let models = InstalledAIModel.claude

    private let defaults: UserDefaults

    /// Empty until the user points at a checkout; nothing can run before they do.
    var repositoryPath: String {
        didSet { defaults.set(repositoryPath, forKey: Key.repositoryPath.rawValue) }
    }
    var baseBranch: String {
        didSet { defaults.set(baseBranch, forKey: Key.baseBranch.rawValue) }
    }
    var model: String {
        didSet { defaults.set(model, forKey: Key.model.rawValue) }
    }
    /// How many times a failed gate may be handed back to the agent before the run gives up.
    var maxAttempts: Int {
        didSet { defaults.set(maxAttempts, forKey: Key.maxAttempts.rawValue) }
    }
    var maxTurns: Int {
        didSet { defaults.set(maxTurns, forKey: Key.maxTurns.rawValue) }
    }
    /// Off leaves a verified branch pushed and stops there, for a request worth reading first.
    var opensPullRequest: Bool {
        didSet { defaults.set(opensPullRequest, forKey: Key.opensPullRequest.rawValue) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        repositoryPath = defaults.string(forKey: Key.repositoryPath.rawValue) ?? ""
        baseBranch = defaults.string(forKey: Key.baseBranch.rawValue) ?? "main"
        model = defaults.string(forKey: Key.model.rawValue) ?? "opus"
        let attempts = defaults.integer(forKey: Key.maxAttempts.rawValue)
        maxAttempts = Self.attemptRange.contains(attempts) ? attempts : 3
        let turns = defaults.integer(forKey: Key.maxTurns.rawValue)
        maxTurns = Self.turnRange.contains(turns) ? turns : 120
        opensPullRequest =
            defaults.object(forKey: Key.opensPullRequest.rawValue) as? Bool ?? true
    }

    var repository: URL? {
        guard !repositoryPath.isEmpty else { return nil }
        return URL(fileURLWithPath: repositoryPath)
    }

    /// The one check the palette makes before accepting a request, so failures surface in Settings.
    var isConfigured: Bool {
        guard let repository else { return false }
        return GitRunner.isTinycastCheckout(repository)
    }

    var configuration: FeatureRequestRunner.Configuration? {
        guard let repository else { return nil }
        return FeatureRequestRunner.Configuration(
            repository: repository, baseBranch: baseBranch, model: model,
            maxAttempts: maxAttempts, maxTurns: maxTurns, opensPullRequest: opensPullRequest)
    }
}
