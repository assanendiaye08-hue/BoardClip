import SwiftUI

@main
struct BoardClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Bindable private var settings = Settings.shared

    var body: some Scene {
        MenuBarExtra(AppInfo.name, systemImage: "doc.on.clipboard", isInserted: $settings.showMenuBarIcon) {
            MenuBarContent()
        }
        .menuBarExtraStyle(.menu)
    }
}
