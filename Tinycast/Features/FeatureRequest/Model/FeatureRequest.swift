import Foundation

/// One "Request a Feature" job: the sentence typed into the palette, and everything it became.
struct FeatureRequest: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let prompt: String
    let branch: String
    let createdAt: Date
    var status: FeatureRequestStatus
    var attempts: [Attempt]
    /// Kept only while a failed run's worktree is still on disk for the user to inspect.
    var worktreePath: String?
    /// The agent session this request has been using, so a follow-up continues rather than restarts.
    var sessionID: String?
    /// Every change asked for after the first build, oldest first.
    var followUps: [String]

    init(
        id: UUID = UUID(), prompt: String, branch: String, createdAt: Date = .now,
        status: FeatureRequestStatus = .queued, attempts: [Attempt] = [],
        worktreePath: String? = nil, sessionID: String? = nil, followUps: [String] = []
    ) {
        self.id = id
        self.prompt = prompt
        self.branch = branch
        self.createdAt = createdAt
        self.status = status
        self.attempts = attempts
        self.worktreePath = worktreePath
        self.sessionID = sessionID
        self.followUps = followUps
    }

    /// One agent run plus the verification that judged it; a retry appends rather than replaces.
    struct Attempt: Identifiable, Codable, Sendable, Equatable {
        let id: Int
        var summary: String
        var changedFiles: Int
        var report: VerificationReport?

        init(id: Int, summary: String = "", changedFiles: Int = 0, report: VerificationReport? = nil)
        {
            self.id = id
            self.summary = summary
            self.changedFiles = changedFiles
            self.report = report
        }
    }

    /// Defaulted rather than required, so a log written before follow-ups existed still decodes.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        prompt = try container.decode(String.self, forKey: .prompt)
        branch = try container.decode(String.self, forKey: .branch)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        status = try container.decode(FeatureRequestStatus.self, forKey: .status)
        attempts = try container.decodeIfPresent([Attempt].self, forKey: .attempts) ?? []
        worktreePath = try container.decodeIfPresent(String.self, forKey: .worktreePath)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        followUps = try container.decodeIfPresent([String].self, forKey: .followUps) ?? []
    }

    /// The row's one-liner: a multi-line request still has to fit on one line of the list.
    var title: String {
        let line = prompt.split(whereSeparator: \.isNewline).first.map(String.init) ?? prompt
        return line.trimmingCharacters(in: .whitespaces)
    }

    var pullRequestURL: URL? {
        if case .opened(let url) = status { return url }
        return nil
    }

    /// The attempt a live run is on, so a row can say "Attempt 2 of 3" without recounting.
    var currentAttempt: Int { max(attempts.count, 1) }

    /// Names this run's directories. Short enough to read in Finder, long enough not to collide.
    var shortID: String { id.uuidString.prefix(8).lowercased() }

    /// True once a run got far enough to have produced a verified build.
    var isVerified: Bool {
        switch status {
        case .opened, .pushed: return true
        default: return false
        }
    }

    /// A follow-up needs somewhere to land: the branch has to exist on the remote already.
    var acceptsFollowUp: Bool { isVerified }
}

/// Where a request is in the pipeline. Persisted, so every case has to survive a relaunch.
enum FeatureRequestStatus: Codable, Sendable, Equatable {
    case queued
    case preparing
    case implementing(attempt: Int)
    case verifying(attempt: Int, step: VerificationReport.Step)
    case publishing
    /// The branch is pushed and verified, but opening the pull request was left to the user.
    case pushed
    case opened(url: URL)
    case failed(reason: String)
    case cancelled

    /// True once nothing more will happen on its own — the queue may start the next request.
    var isFinished: Bool {
        switch self {
        case .opened, .pushed, .failed, .cancelled: return true
        case .queued, .preparing, .implementing, .verifying, .publishing: return false
        }
    }

    /// True while a process is actually running, which is what the row spins on.
    var isRunning: Bool { !isFinished && self != .queued }

    var label: String {
        switch self {
        case .queued: return "Queued"
        case .preparing: return "Preparing worktree"
        case .implementing(let attempt): return "Building — attempt \(attempt)"
        case .verifying(_, let step): return "Verifying — \(step.title)"
        case .publishing: return "Opening pull request"
        case .pushed: return "Branch pushed"
        case .opened: return "Pull request opened"
        case .failed(let reason): return reason
        case .cancelled: return "Cancelled"
        }
    }

    var symbol: String {
        switch self {
        case .queued: return "clock"
        case .preparing, .implementing, .verifying, .publishing: return "gearshape.2"
        case .pushed: return "arrow.up.circle.fill"
        case .opened: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "slash.circle"
        }
    }
}
