import Foundation

/// On-disk locations for history JSON and external image/file blobs.
enum AppPaths {
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(AppInfo.name, isDirectory: true)
    }()

    static var historyFile: URL { support.appendingPathComponent("history.json") }
    static var spacesFile: URL { support.appendingPathComponent("spaces.json") }
    static var blobsDir: URL { support.appendingPathComponent("blobs", isDirectory: true) }

    /// Create the directory tree if it doesn't exist yet. Safe to call repeatedly.
    static func ensure() {
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: blobsDir, withIntermediateDirectories: true)
    }

    static func blobURL(_ name: String) -> URL { blobsDir.appendingPathComponent(name) }
}
