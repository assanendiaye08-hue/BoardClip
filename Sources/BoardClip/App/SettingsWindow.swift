import SwiftUI
import AppKit

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if let window {
            present(window)
            return
        }

        let hosting = NSHostingView(rootView: SettingsView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 430),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(AppInfo.name) Settings"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.contentView = hosting
        self.window = window

        present(window)
    }

    private static func present(_ window: NSWindow) {
        placeOnCurrentScreen(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private static func placeOnCurrentScreen(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else {
            window.center()
            return
        }

        var origin = NSPoint(
            x: frame.midX - window.frame.width / 2,
            y: frame.midY - window.frame.height / 2
        )
        origin.x = min(max(origin.x, frame.minX), frame.maxX - window.frame.width)
        origin.y = min(max(origin.y, frame.minY), frame.maxY - window.frame.height)
        window.setFrameOrigin(origin)
    }
}
