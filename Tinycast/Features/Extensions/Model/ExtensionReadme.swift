import Foundation

/// A listing's README as a registry hands it over: a browse URL, relative links, and no size cap.
enum ExtensionReadme {
    /// Larger than any real extension README, and small enough that one can't stall the preview.
    static let byteLimit = 256 * 1024

    /// `github.com/<owner>/<repo>/tree/<ref>/<path>` is a page; only its raw twin is fetchable.
    static func rawURL(from url: URL) -> URL? {
        guard let host = url.host() else { return nil }
        if host == "raw.githubusercontent.com" { return url }
        guard host == "github.com" || host == "www.github.com" else { return nil }
        var parts = url.path(percentEncoded: false).split(separator: "/").map(String.init)
        guard parts.count > 4 else { return nil }
        let marker = parts.remove(at: 2)
        guard marker == "tree" || marker == "blob" || marker == "raw" else { return nil }
        let escaped =
            parts.joined(separator: "/").addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed) ?? ""
        return URL(string: "https://raw.githubusercontent.com/\(escaped)")
    }

    /// What a relative link inside that README resolves against — the directory holding it.
    static func assetsBase(forRaw url: URL) -> URL {
        url.deletingLastPathComponent()
    }

    /// A relative image target is the one thing the markdown view has no way to resolve itself.
    static func absoluteImages(in markdown: String, base: URL) -> String {
        var result = ""
        var rest = Substring(markdown)
        while let open = rest.range(of: "![") {
            guard let separator = rest[open.upperBound...].range(of: "]("),
                let close = rest[separator.upperBound...].firstIndex(of: ")")
            else { break }
            let target = rest[separator.upperBound..<close]
            result += rest[..<separator.upperBound]
            result += rewrite(String(target), base: base)
            rest = rest[close...]
        }
        return result + rest
    }

    /// Decoded and capped: a README is shown, never stored, so an oversized one is simply cut.
    static func decoded(_ data: Data) -> String? {
        String(data: data.prefix(byteLimit), encoding: .utf8)
    }

    /// The title part of `(path "title")` rides along untouched; only the target is rewritten.
    private static func rewrite(_ target: String, base: URL) -> String {
        let pieces = target.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard let path = pieces.first.map(String.init), !path.isEmpty else { return target }
        let title = pieces.count > 1 ? " " + pieces[1] : ""
        guard isRelative(path) else { return target }
        let cleaned = path.hasPrefix("./") ? String(path.dropFirst(2)) : path
        let resolved = URL(string: cleaned, relativeTo: base)?.absoluteURL
        return (resolved?.absoluteString ?? path) + title
    }

    /// An anchor and a protocol-relative URL are both absolute enough to leave alone.
    private static func isRelative(_ path: String) -> Bool {
        guard !path.hasPrefix("#"), !path.hasPrefix("//") else { return false }
        return URL(string: path)?.scheme == nil
    }
}
