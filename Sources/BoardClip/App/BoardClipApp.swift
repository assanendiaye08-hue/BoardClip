import SwiftUI

@main
struct BoardClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra(AppInfo.name, systemImage: "doc.on.clipboard") {
            MenuBarContent()
        }
        .menuBarExtraStyle(.menu)

        SwiftUI.Settings {
            SettingsView()
        }
    }
}
