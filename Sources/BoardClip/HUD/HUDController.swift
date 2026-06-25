import AppKit
import SwiftUI

/// Per-open signal the HUD observes to reset its search/selection each time it's summoned
/// (the hosting view is reused across opens, so `onAppear` only fires once).
@MainActor
@Observable
final class HUDSession {
    var openCount = 0
}

/// Owns the floating HUD: builds it, pins it to the top of the active screen, shows/hides it,
/// remembers which app was focused, and routes paste actions back through `Paster`.
@MainActor
final class HUDController: NSObject, NSWindowDelegate {
    private let store: HistoryStore
    private let spaceStore: SpaceStore
    private let settings: Settings
    private let monitor: ClipboardMonitor

    private let session = HUDSession()
    private var panel: HUDPanel?
    private var previousApp: NSRunningApplication?
    private var modalActive = false

    init(store: HistoryStore, spaceStore: SpaceStore, settings: Settings, monitor: ClipboardMonitor) {
        self.store = store
        self.spaceStore = spaceStore
        self.settings = settings
        self.monitor = monitor
        super.init()
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        guard let panel, panel.isVisible, panel.isKeyWindow else {
            show()
            return
        }
        hide()
    }

    func show() {
        // Remember what was focused so we can paste back into it. Never capture ourselves —
        // the panel is non-activating, so the real previous app should always be frontmost here.
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != AppInfo.bundleID {
            previousApp = front
        }
        let panel = makePanel()
        panel.orderOut(nil)
        position(panel)
        session.openCount += 1   // tell the view to reset search/selection + refocus
        // Non-activating: the panel becomes key and receives keystrokes WITHOUT activating the app,
        // so the previously focused text field stays frontmost and paste-back is just ⌘V.
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: Building

    private func makePanel() -> HUDPanel {
        if let panel { return panel }

        let view = HUDView(
            store: store,
            spaceStore: spaceStore,
            settings: settings,
            session: session,
            onPaste: { [weak self] item, plain in self?.paste(item, plain: plain) },
            onClose: { [weak self] in self?.hide() },
            onAddSpace: { [weak self] in self?.addSpace() },
            onTogglePin: { [weak self] item in self?.store.togglePin(item) },
            onDelete: { [weak self] item in self?.store.delete(item) },
            onToggleSpace: { [weak self] sid, item in self?.store.toggleSpace(sid, for: item) },
            onEditSpaceNote: { [weak self] item, sid in self?.editSpaceNote(item, in: sid) },
            onSaveToPhotos: { item in ItemActions.saveToPhotos(item) },
            onResearch: { [weak self] item in self?.hide(); ItemActions.research(item) },
            onReveal: { [weak self] item in self?.hide(); ItemActions.revealInFinder(item) },
            onTransformPaste: { [weak self] item, transform in self?.transformPaste(item, transform) },
            onSettings: { [weak self] in self?.showSettings() }
        )

        let hosting = NSHostingView(rootView: view)
        hosting.autoresizingMask = [.width, .height]

        let panel = HUDPanel(contentRect: NSRect(x: 0, y: 0, width: 800, height: Design.panelHeight))
        panel.delegate = self
        panel.contentView = hosting
        self.panel = panel
        return panel
    }

    private func position(_ panel: HUDPanel) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        guard let screen else { return }
        // Pasty-style: a full-width bar pinned flush under the menu bar at the very top of the screen.
        let full = screen.frame
        let visible = screen.visibleFrame
        let height = Design.panelHeight
        let frame = NSRect(x: full.minX, y: visible.maxY - height, width: full.width, height: height)
        panel.setFrame(frame, display: true)
    }

    // MARK: Paste

    private func paste(_ item: ClipItem, plain: Bool) {
        hide()
        Paster.paste(item, asPlainText: plain, previousApp: previousApp, monitor: monitor, store: store)
    }

    private func transformPaste(_ item: ClipItem, _ transform: ItemActions.Transform) {
        var temp = item
        temp.kind = .text
        temp.text = transform.apply(item.bestPlainText)
        hide()
        Paster.paste(temp, asPlainText: true, previousApp: previousApp, monitor: monitor, store: store)
    }

    private func showSettings() {
        hide()
        SettingsWindow.show()
    }

    private func addSpace() {
        let alert = NSAlert()
        alert.messageText = "New Space"
        alert.informativeText = "Spaces are durable boards. Right-click any clip → Add to Space to keep it here for good."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "e.g. Snippets"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        modalActive = true               // keep the HUD open behind the sheet
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        modalActive = false

        if response == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { spaceStore.add(name: name) }
        }
        panel?.makeKeyAndOrderFront(nil)
    }

    private func editSpaceNote(_ item: ClipItem, in spaceID: UUID) {
        let alert = NSAlert()
        alert.messageText = item.note(in: spaceID) == nil ? "Add Note" : "Edit Note"
        alert.informativeText = "This note replaces the source label on the clip card in this Space. Leave it blank to show the source again."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = item.sourceAppName ?? item.kind.label
        field.stringValue = item.note(in: spaceID) ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        modalActive = true
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        modalActive = false

        if response == .alertFirstButtonReturn {
            store.setSpaceNote(field.stringValue, for: item, in: spaceID)
        }
        panel?.makeKeyAndOrderFront(nil)
    }

    // MARK: NSWindowDelegate — dismiss when the user clicks away

    func windowDidResignKey(_ notification: Notification) {
        guard !modalActive else { return }
        hide()
    }
}
