import Foundation

/// One path `git status --porcelain` reported, parsed so nothing downstream re-reads the format.
struct WorktreeChange: Sendable, Equatable {
    let path: String
    let isAdded: Bool
    let isDeleted: Bool

    /// Porcelain v1: two status columns, a space, then the path — renames arrive as `old -> new`.
    static func parse(porcelain: String) -> [WorktreeChange] {
        porcelain.split(whereSeparator: \.isNewline).compactMap { line in
            guard line.count > 3 else { return nil }
            let code = String(line.prefix(2))
            let rest = String(line.dropFirst(3))
            guard let path = destination(of: rest) else { return nil }
            // A rename reads as `R`, never `D`: moving a file is not deleting it.
            return WorktreeChange(
                path: path, isAdded: code.contains("?") || code.contains("A"),
                isDeleted: code.contains("D"))
        }
    }

    /// A rename's new name is the one that has to exist in the project file.
    private static func destination(of rest: String) -> String? {
        let path = rest.components(separatedBy: " -> ").last ?? rest
        // Git quotes any path it had to escape; the quotes are not part of the name.
        let unquoted =
            path.hasPrefix("\"") && path.hasSuffix("\"") && path.count > 1
            ? String(path.dropFirst().dropLast()) : path
        let trimmed = unquoted.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
