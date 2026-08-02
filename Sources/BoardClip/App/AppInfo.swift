import Foundation

/// Central place for app identity. Rename the product here and in `Package.swift`.
enum AppInfo {
    static let name = "BoardClip"
    static let bundleID = "com.boardclip.app"

    /// Marketing version (kept in sync with the bundle's Info.plist at package time).
    static let version = "0.1.21"

    /// GitHub "owner/repo" — used for the update feed and "Report an issue".
    static let githubRepo = "assanendiaye08-hue/BoardClip"

    static var githubURL: URL { URL(string: "https://github.com/\(githubRepo)")! }
}
