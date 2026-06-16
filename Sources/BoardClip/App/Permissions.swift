import AppKit
import ApplicationServices
import ServiceManagement

/// Accessibility is required to synthesize ⌘V into the previously focused app.
@MainActor
enum Permissions {
    static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt and registers the app in the Accessibility list.
    @discardableResult
    static func promptAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Login-item registration via the modern ServiceManagement API (no helper bundle needed).
@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            NSLog("[BoardClip] launch-at-login toggle failed: \(error.localizedDescription)")
        }
    }
}
