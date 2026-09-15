import Foundation

/// Catches the silent half of forgetting `xcodegen generate`: the build passes, minus the new code.
///
/// `project.yml` globs a folder, but generation bakes that into explicit references — so a source
/// file added without regenerating compiles in the harnesses and is simply absent from the app.
enum ProjectSync {
    /// Sources the app would compile if they were referenced; `Tests/` is built by its own script.
    static func compilableSources(in changes: [WorktreeChange]) -> [String] {
        changes
            .filter { $0.isAdded && $0.path.hasSuffix(".swift") && $0.path.hasPrefix("Tinycast/") }
            .map(\.path)
    }

    /// Matched on file name, which is what the project file stores; a shipped name is unique here.
    static func unreferenced(sources: [String], inProject project: String) -> [String] {
        sources.filter { path in
            guard let name = path.split(separator: "/").last else { return false }
            return !project.contains("path = \(name);") && !project.contains("/* \(name) */")
        }
    }

    /// The failing digest, phrased as the command that fixes it rather than as a list of paths.
    static func digest(unreferenced: [String]) -> String {
        let list = unreferenced.map { "  " + $0 }.joined(separator: "\n")
        return """
            These files are not in Tinycast.xcodeproj, so the app builds without them:
            \(list)

            Run `xcodegen generate` and commit the regenerated project alongside the sources.
            """
    }
}
