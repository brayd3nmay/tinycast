import Foundation

/// The README a store listing points at: a browse URL, relative links, and no size cap.
@main
@MainActor
struct ExtensionReadmeTests {
    static var failures = 0
    static var passes = 0

    static func main() {
        rawURLs()
        relativeImages()
        decoding()

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        print("\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Raw URLs

    static func rawURLs() {
        print("\n# raw urls")

        let tree = URL(
            string: "https://github.com/raycast/extensions/tree/abc123/extensions/coffee/README.md")!
        check(
            "a tree link becomes a raw one",
            ExtensionReadme.rawURL(from: tree)?.absoluteString
                == "https://raw.githubusercontent.com/raycast/extensions/abc123/extensions/coffee/README.md")

        let blob = URL(
            string: "https://github.com/me/repo/blob/main/docs/README.md")!
        check(
            "a blob link works the same",
            ExtensionReadme.rawURL(from: blob)?.absoluteString
                == "https://raw.githubusercontent.com/me/repo/main/docs/README.md")

        let raw = URL(string: "https://raw.githubusercontent.com/me/repo/main/README.md")!
        check("an already-raw URL is left alone", ExtensionReadme.rawURL(from: raw) == raw)

        let spaced = URL(string: "https://github.com/me/repo/tree/main/my%20ext/README.md")!
        check(
            "a percent-escaped path survives one round trip",
            ExtensionReadme.rawURL(from: spaced)?.absoluteString
                == "https://raw.githubusercontent.com/me/repo/main/my%20ext/README.md")

        check(
            "a repository root has no file to fetch",
            ExtensionReadme.rawURL(from: URL(string: "https://github.com/me/repo")!) == nil)
        check(
            "a path with no tree marker is rejected",
            ExtensionReadme.rawURL(from: URL(string: "https://github.com/me/repo/wiki/Page/x")!) == nil)
        check(
            "another host is rejected",
            ExtensionReadme.rawURL(from: URL(string: "https://example.com/a/b/tree/c/d")!) == nil)

        let base = ExtensionReadme.assetsBase(
            forRaw: URL(
                string: "https://raw.githubusercontent.com/me/repo/main/extensions/coffee/README.md")!)
        check(
            "the assets base is the README's own directory",
            base.absoluteString
                == "https://raw.githubusercontent.com/me/repo/main/extensions/coffee/")
    }

    // MARK: - Images

    static func relativeImages() {
        print("\n# relative images")
        let base = URL(string: "https://raw.githubusercontent.com/me/repo/main/extensions/coffee/")!

        check(
            "a relative target is resolved",
            ExtensionReadme.absoluteImages(in: "![cup](metadata/1.png)", base: base)
                == "![cup](https://raw.githubusercontent.com/me/repo/main/extensions/coffee/metadata/1.png)")

        check(
            "a leading ./ is dropped first",
            ExtensionReadme.absoluteImages(in: "![cup](./assets/icon.png)", base: base)
                == "![cup](https://raw.githubusercontent.com/me/repo/main/extensions/coffee/assets/icon.png)")

        check(
            "an absolute target is left alone",
            ExtensionReadme.absoluteImages(in: "![x](https://example.com/a.png)", base: base)
                == "![x](https://example.com/a.png)")

        check(
            "a protocol-relative target is left alone",
            ExtensionReadme.absoluteImages(in: "![x](//example.com/a.png)", base: base)
                == "![x](//example.com/a.png)")

        check(
            "a data URL is left alone",
            ExtensionReadme.absoluteImages(in: "![x](data:image/png;base64,AA)", base: base)
                == "![x](data:image/png;base64,AA)")

        check(
            "a title rides along untouched",
            ExtensionReadme.absoluteImages(in: #"![x](a.png "A cup")"#, base: base)
                == #"![x](https://raw.githubusercontent.com/me/repo/main/extensions/coffee/a.png "A cup")"#)

        let many = ExtensionReadme.absoluteImages(
            in: "# Coffee\n\n![a](a.png)\n\ntext ![b](b.png) tail\n", base: base)
        check("every image in the body is rewritten", !many.contains("](a.png)") && !many.contains("](b.png)"))
        check("the surrounding text is kept", many.hasPrefix("# Coffee") && many.hasSuffix(" tail\n"))

        check(
            "a link that is not an image is untouched",
            ExtensionReadme.absoluteImages(in: "[docs](docs.md)", base: base) == "[docs](docs.md)")

        // An unterminated image would otherwise drop everything after it.
        check(
            "a half-written image is left whole",
            ExtensionReadme.absoluteImages(in: "before ![oops", base: base) == "before ![oops")
        check(
            "an unclosed target is left whole",
            ExtensionReadme.absoluteImages(in: "![a](b.png", base: base) == "![a](b.png")
        check(
            "an empty target is left whole",
            ExtensionReadme.absoluteImages(in: "![a]()", base: base) == "![a]()")
        check("an empty document stays empty", ExtensionReadme.absoluteImages(in: "", base: base) == "")
    }

    // MARK: - Decoding

    static func decoding() {
        print("\n# decoding")
        check("plain text decodes", ExtensionReadme.decoded(Data("# Hi".utf8)) == "# Hi")

        let oversized = Data(String(repeating: "a", count: ExtensionReadme.byteLimit + 500).utf8)
        check(
            "an oversized README is cut to the cap",
            ExtensionReadme.decoded(oversized)?.count == ExtensionReadme.byteLimit)
    }

    // MARK: - Harness

    static func check(_ label: String, _ condition: Bool) {
        if condition {
            passes += 1
            print("  ok   \(label)")
        } else {
            failures += 1
            print("  FAIL \(label)")
        }
    }
}
