import SwiftUI

/// The menu shown when clicking the menu-bar icon.
struct MenuBarContent: View {
    var body: some View {
        Button("Show \(AppInfo.name)") { AppDelegate.shared?.showHUD() }

        Divider()

        Button("Clear History") { AppDelegate.shared?.store.clearAll() }

        if !Permissions.accessibilityGranted {
            Button("Enable Paste (Accessibility)…") {
                Permissions.promptAccessibility()
                Permissions.openAccessibilitySettings()
            }
        }

        Divider()

        Button("Settings…") { AppDelegate.shared?.showSettings() }
            .keyboardShortcut(",", modifiers: .command)
        Button("Welcome / Setup…") { AppDelegate.shared?.showOnboarding() }
        Button("Check for Updates…") { AppDelegate.shared?.checkForUpdates() }

        Divider()

        Button("Quit \(AppInfo.name)") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
