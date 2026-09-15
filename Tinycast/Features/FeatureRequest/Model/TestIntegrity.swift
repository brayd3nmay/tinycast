import Foundation

/// Stops the cheapest way to make a red suite green: removing the thing that was failing.
///
/// The other gates check that the suite passes, not that it still proves anything. Deleting a
/// harness, or dropping its `run` line from the script that dispatches it, does both at once.
enum TestIntegrity {
    /// `run-tests.sh` is in here because a harness with no `run` line is a harness that never runs.
    static let dispatcher = "Scripts/run-tests.sh"

    static func isGuarded(_ path: String) -> Bool {
        (path.hasPrefix("Tests/") && path.hasSuffix(".swift")) || path == dispatcher
    }

    struct Delta: Sendable, Equatable {
        let path: String
        let added: Int
        let removed: Int

        var shrank: Bool { removed > added }
    }

    /// `git diff --numstat -M`: added, removed, path — where a rename's path names its destination.
    static func parse(numstat: String) -> [Delta] {
        numstat.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.components(separatedBy: "\t")
            guard fields.count >= 3, let added = Int(fields[0]), let removed = Int(fields[1]) else {
                return nil  // `-` in both columns is a binary file, which has no lines to lose.
            }
            return Delta(path: destination(of: fields[2]), added: added, removed: removed)
        }
    }

    /// Renames arrive as `dir/{old => new}.swift`, or as a bare `old => new` when no prefix is shared.
    private static func destination(of path: String) -> String {
        guard let open = path.firstIndex(of: "{"), let close = path.firstIndex(of: "}"),
            open < close
        else {
            return path.components(separatedBy: " => ").last ?? path
        }
        let inner = path[path.index(after: open)..<close]
        let new = inner.components(separatedBy: " => ").last ?? String(inner)
        return path[..<open] + new + path[path.index(after: close)...]
    }

    /// One line per regression, phrased as what happened rather than as a rule that was broken.
    static func regressions(changes: [WorktreeChange], deltas: [Delta]) -> [String] {
        var found = changes
            .filter { $0.isDeleted && isGuarded($0.path) }
            .map { "\($0.path) was deleted" }
        let deleted = Set(changes.filter(\.isDeleted).map(\.path))
        for delta in deltas
        where isGuarded(delta.path) && delta.shrank && !deleted.contains(delta.path) {
            let lost = delta.removed - delta.added
            found.append(
                "\(delta.path) lost \(lost) line\(lost == 1 ? "" : "s") "
                    + "(added \(delta.added), removed \(delta.removed))")
        }
        return found
    }

    static func digest(regressions: [String]) -> String {
        """
        The test suite got weaker, which is never how a gate is allowed to pass:
        \(regressions.map { "  " + $0 }.joined(separator: "\n"))

        Restore what you removed. If a test is genuinely wrong, say so in your final message and
        leave it failing rather than deleting it.
        """
    }
}
