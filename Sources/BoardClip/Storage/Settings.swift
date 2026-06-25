import Foundation
import Observation
import AppKit

/// User preferences, persisted to `UserDefaults`. Observable so SwiftUI reacts to changes.
@MainActor
@Observable
final class Settings {
    static let shared = Settings()

    private let d = UserDefaults.standard

    var pollInterval: Double { didSet { d.set(pollInterval, forKey: "pollInterval") } }
    var maxItems: Int { didSet { d.set(maxItems, forKey: "maxItems") } }
    var retentionDays: Int { didSet { d.set(retentionDays, forKey: "retentionDays") } }
    var ignoreConcealed: Bool { didSet { d.set(ignoreConcealed, forKey: "ignoreConcealed") } }
    var watchScreenshots: Bool { didSet { d.set(watchScreenshots, forKey: "watchScreenshots") } }
    var copyScreenshotsToClipboard: Bool { didSet { d.set(copyScreenshotsToClipboard, forKey: "copyScreenshotsToClipboard") } }
    var pasteAsPlainDefault: Bool { didSet { d.set(pasteAsPlainDefault, forKey: "pasteAsPlainDefault") } }
    var clipScrollSensitivity: Double { didSet { d.set(clipScrollSensitivity, forKey: "clipScrollSensitivity") } }
    var showMenuBarIcon: Bool { didSet { d.set(showMenuBarIcon, forKey: "showMenuBarIcon") } }
    var playSounds: Bool { didSet { d.set(playSounds, forKey: "playSounds") } }

    /// Global hotkey. `keyCode` is a virtual key code; `modifiers` is `NSEvent.ModifierFlags.rawValue`.
    var hotKeyCode: Int { didSet { d.set(hotKeyCode, forKey: "hotKeyCode") } }
    var hotKeyModifiers: UInt { didSet { d.set(Int(bitPattern: hotKeyModifiers), forKey: "hotKeyModifiers") } }

    var excludedBundleIDs: [String] { didSet { d.set(excludedBundleIDs, forKey: "excludedBundleIDs") } }

    private init() {
        pollInterval = (d.object(forKey: "pollInterval") as? Double) ?? 0.5
        maxItems = (d.object(forKey: "maxItems") as? Int) ?? 1000
        retentionDays = (d.object(forKey: "retentionDays") as? Int) ?? 30
        ignoreConcealed = (d.object(forKey: "ignoreConcealed") as? Bool) ?? true
        watchScreenshots = (d.object(forKey: "watchScreenshots") as? Bool) ?? true
        copyScreenshotsToClipboard = (d.object(forKey: "copyScreenshotsToClipboard") as? Bool) ?? true
        pasteAsPlainDefault = (d.object(forKey: "pasteAsPlainDefault") as? Bool) ?? false
        clipScrollSensitivity = (d.object(forKey: "clipScrollSensitivity") as? Double) ?? 0.35
        showMenuBarIcon = (d.object(forKey: "showMenuBarIcon") as? Bool) ?? true
        playSounds = (d.object(forKey: "playSounds") as? Bool) ?? false
        hotKeyCode = (d.object(forKey: "hotKeyCode") as? Int) ?? 9 // 'v'
        hotKeyModifiers = (d.object(forKey: "hotKeyModifiers") as? Int)
            .map { UInt(bitPattern: $0) }
            ?? (NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.option.rawValue)
        excludedBundleIDs = (d.object(forKey: "excludedBundleIDs") as? [String]) ?? []
    }

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: hotKeyModifiers) }
}
