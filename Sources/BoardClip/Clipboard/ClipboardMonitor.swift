import AppKit

/// Polls the general pasteboard for changes (it has no change notification) and emits drafts.
@MainActor
final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private let settings: Settings
    private var timer: Timer?
    private var lastChangeCount: Int

    /// Set so we don't re-capture a clip we just placed on the pasteboard ourselves.
    var suppressedChangeCount: Int = -1

    var onNewDraft: ((PasteboardDraft) -> Void)?

    init(settings: Settings) {
        self.settings = settings
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        stop()
        let t = Timer.scheduledTimer(withTimeInterval: settings.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        t.tolerance = settings.pollInterval / 4
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func restart() { start() }

    private func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        if count == suppressedChangeCount { return }
        if let draft = PasteboardReader.read(pasteboard, settings: settings) {
            onNewDraft?(draft)
        }
    }
}
