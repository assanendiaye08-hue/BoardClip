import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) weak var shared: AppDelegate?

    let settings = Settings.shared
    private(set) var store: HistoryStore!
    private(set) var spaceStore: SpaceStore!
    private(set) var monitor: ClipboardMonitor!
    private(set) var hud: HUDController!
    private(set) var updater: UpdaterController!
    private var screenshotWatcher: ScreenshotWatcher?
    private var retentionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        // Menu-bar agent: no Dock icon, no app menu.
        NSApp.setActivationPolicy(.accessory)
        AppPaths.ensure()

        store = HistoryStore(settings: settings)
        store.load()
        store.cleanup()

        spaceStore = SpaceStore()
        spaceStore.load()
        if !UserDefaults.standard.bool(forKey: "didSeedSpaces") {
            UserDefaults.standard.set(true, forKey: "didSeedSpaces")
            if spaceStore.spaces.isEmpty {
                spaceStore.add(name: "Saved", symbol: "star", colorHex: "#FF9F0A")
                spaceStore.add(name: "Snippets", symbol: "chevron.left.forwardslash.chevron.right", colorHex: "#0A84FF")
            }
        }

        monitor = ClipboardMonitor(settings: settings)
        monitor.onNewDraft = { [weak self] draft in self?.store.ingest(draft) }
        monitor.start()

        screenshotWatcher = ScreenshotWatcher(store: store, settings: settings, monitor: monitor)
        if settings.watchScreenshots { screenshotWatcher?.start() }

        hud = HUDController(store: store, spaceStore: spaceStore, settings: settings, monitor: monitor)

        HotKeyManager.shared.onActivate = { [weak self] in self?.hud.toggle() }
        HotKeyManager.shared.register(keyCode: settings.hotKeyCode, flags: settings.modifierFlags)

        updater = UpdaterController()

        // Periodic retention sweep (also runs on launch above).
        let t = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.cleanup() }
        }
        retentionTimer = t

        showOnboardingIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.flush()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if settings.showMenuBarIcon {
            showHUD()
        } else {
            showSettings()
        }
        return true
    }

    // MARK: Public hooks (used by Settings / menu)

    @discardableResult
    func reloadHotKey() -> Bool {
        HotKeyManager.shared.register(keyCode: settings.hotKeyCode, flags: settings.modifierFlags)
    }

    func setScreenshotWatching(_ enabled: Bool) {
        if enabled { screenshotWatcher?.start() } else { screenshotWatcher?.stop() }
    }

    func restartMonitor() { monitor?.restart() }

    func showHUD() { hud?.show() }

    func showSettings() { SettingsWindow.show() }

    func showOnboarding() { OnboardingWindow.show() }

    func checkForUpdates() {
        updater?.checkForUpdates()
    }

    func confirmClearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear Clipboard History?"
        alert.informativeText = "Pinned clips and clips saved to a Space will be kept."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            store.clearAll()
        }
    }

    private func showOnboardingIfNeeded() {
        let key = "didOnboard"
        if !UserDefaults.standard.bool(forKey: key) {
            OnboardingWindow.show()
        }
    }
}
