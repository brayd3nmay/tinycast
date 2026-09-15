import Foundation

/// Which kept preview builds have outlived their usefulness. Pure, so the sweep is testable.
enum PreviewRetention {
    /// Three: enough to compare a change against the two before it, and 141MB rather than 2GB.
    static let limit = 3

    /// Everything on disk that is not among the newest `limit` live runs, minus whatever is running.
    ///
    /// `live` is newest-first, so a preview falls off the end the same way its request does.
    static func expired(
        onDisk: [String], live: [String], limit: Int = limit, running: String? = nil
    ) -> [String] {
        let kept = Set(live.filter(onDisk.contains).prefix(limit))
        return onDisk.filter { $0 != running && !kept.contains($0) }
    }
}
