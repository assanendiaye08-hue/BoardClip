import SwiftUI

/// The menu shown when clicking the menu-bar icon.
struct MenuBarContent: View {
    @Bindable private var settings = Settings.shared

    var body: some View {
        Button("Show \(AppInfo.name)") { AppDelegate.shared?.showHUD() }

        Button(settings.captureClipboard ? "Pause Clipboard Capture" : "Resume Clipboard Capture") {
            settings.captureClipboard.toggle()
        }

        Divider()

        Button("Clear History…") { AppDelegate.shared?.confirmClearHistory() }

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
