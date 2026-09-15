import Foundation

/// Turns a typed sentence into the git and GitHub names the run will use. Pure, so it is testable.
enum FeatureBranch {
    static let prefix = "feature/"
    private static let slugLimit = 48
    private static let titleLimit = 72

    /// `feature/<slug>-<short id>`: two identically worded requests must not land on one branch.
    static func name(prompt: String, id: UUID) -> String {
        let stem = slug(prompt)
        let short = id.uuidString.prefix(6).lowercased()
        return prefix + (stem.isEmpty ? "request" : stem) + "-" + short
    }

    /// Lowercase ASCII words joined by single hyphens — everything git refuses, collapsed away.
    static func slug(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en"))
        var words: [String] = []
        var current = ""
        for character in folded.lowercased() {
            if character.isASCII, character.isLetter || character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }

        var slug = ""
        for word in words {
            if slug.isEmpty {
                slug = word
            } else if slug.count + 1 + word.count <= slugLimit {
                slug += "-" + word
            } else {
                break
            }
        }
        return String(slug.prefix(slugLimit))
    }

    /// Sentence case, clipped on a word boundary: a PR title is a headline, not the whole request.
    static func title(prompt: String) -> String {
        let line =
            prompt
            .split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !line.isEmpty else { return "Implement requested feature" }
        guard line.count > titleLimit else { return line }
        let clipped = line.prefix(titleLimit)
        guard let cut = clipped.lastIndex(of: " ") else { return String(clipped) + "…" }
        return clipped[..<cut].trimmingCharacters(in: .whitespaces) + "…"
    }

    static func commitMessage(prompt: String) -> String {
        title(prompt: prompt)
    }

    /// The PR body: the request verbatim, then what the run actually proved before opening it.
    static func body(request: FeatureRequest, report: VerificationReport?) -> String {
        var lines = ["### Request", "", request.prompt, "", "### Verification", ""]
        let checks = report?.summaryLines ?? ["(not run)"]
        lines += checks.map { "- " + $0 }
        if request.attempts.count > 1 {
            lines += ["", "Took \(request.attempts.count) attempts."]
        }
        lines += ["", "Requested from Tinycast and built by an agent; review before merging."]
        return lines.joined(separator: "\n")
    }
}
