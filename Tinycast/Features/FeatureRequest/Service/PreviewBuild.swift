import Foundation

/// The runnable half of a verified run: the app the build gate produced, kept so it can be opened.
///
/// It is its own channel — `Tinycast Preview`, `com.tinycast.app.preview` — so it launches beside
/// whatever Tinycast the user is already running instead of fighting it for a bundle identifier.
enum PreviewBuild {
    static let bundleID = "com.tinycast.app.preview"
    static let productName = "Tinycast Preview"
    static var appName: String { productName + ".app" }

    /// Passed on the `xcodebuild` line, the way `release.yml` already names a channel.
    ///
    /// The icon is named too: the gate builds Debug, so without it a preview wears the dev hammer.
    static var buildSettings: [String] {
        [
            "PRODUCT_NAME=" + productName, "PRODUCT_BUNDLE_IDENTIFIER=" + bundleID,
            "ASSETCATALOG_COMPILER_APPICON_NAME=tinycast-preview"
        ]
    }

    /// Caches, not Application Support: a preview is reproducible, so macOS may purge it freely.
    static var root: URL {
        AppPaths.caches().appending(path: "feature-request-previews")
    }

    static func location(for shortID: String) -> URL {
        root.appending(path: shortID).appending(path: appName)
    }

    static func exists(for shortID: String) -> Bool {
        FileManager.default.fileExists(atPath: location(for: shortID).path)
    }

    static func onDisk() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: root.path))?
            .filter { !$0.hasPrefix(".") } ?? []
    }

    /// Copied out of the shared derived data, which the next run overwrites.
    static func preserve(from derivedData: URL, for shortID: String) throws {
        let built = derivedData
            .appending(path: "Build/Products/Debug")
            .appending(path: appName)
        guard FileManager.default.fileExists(atPath: built.path) else {
            throw SubprocessRunner.Failure(reason: "The build produced no app to keep.")
        }
        let destination = location(for: shortID)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: built, to: destination)
    }

    static func discard(_ shortID: String) {
        try? FileManager.default.removeItem(at: root.appending(path: shortID))
    }

    /// The channel's own prefs and data, which live outside `root` and outlive every preview in it.
    ///
    /// Only safe once nothing is left to run: the directory is shared by every preview, because
    /// they all carry the one bundle identifier.
    static func discardChannelData() {
        UserDefaults().removePersistentDomain(forName: bundleID)
        try? FileManager.default.removeItem(at: AppPaths.applicationSupport(bundleID: bundleID))
        try? FileManager.default.removeItem(at: AppPaths.caches(bundleID: bundleID))
    }
}
