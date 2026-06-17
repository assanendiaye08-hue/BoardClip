import AppKit

/// Watches the macOS screenshot folder so ⌘⇧4 *file* screenshots are captured too
/// (the clipboard monitor only sees ⌘⌃⇧4 screenshots that go to the pasteboard).
@MainActor
final class ScreenshotWatcher {
    private let store: HistoryStore
    private let settings: Settings
    private let monitor: ClipboardMonitor
    private var source: DispatchSourceFileSystemObject?
    private var known: Set<String> = []
    private let dirURL: URL
    private let namePrefix: String

    init(store: HistoryStore, settings: Settings, monitor: ClipboardMonitor) {
        self.store = store
        self.settings = settings
        self.monitor = monitor
        let d = UserDefaults(suiteName: "com.apple.screencapture")
        if let loc = d?.string(forKey: "location"), !loc.isEmpty {
            dirURL = URL(fileURLWithPath: (loc as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            dirURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory() + "/Desktop", isDirectory: true)
        }
        let custom = d?.string(forKey: "name")
        namePrefix = (custom?.isEmpty == false) ? custom! : "Screen" // "Screenshot" / "Screen Shot"
    }

    func start() {
        stop()
        known = matchingFiles()
        let fd = open(dirURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .extend], queue: .main)
        src.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.scan() } }
        // Capture `fd` by value so a later start() can't make this handler close the new descriptor.
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func matchingFiles() -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dirURL.path)) ?? []
        return Set(names.filter(isScreenshot))
    }

    private func isScreenshot(_ name: String) -> Bool {
        let l = name.lowercased()
        let isImage = l.hasSuffix(".png") || l.hasSuffix(".jpg") || l.hasSuffix(".jpeg")
        return isImage && name.hasPrefix(namePrefix)
    }

    private func scan() {
        let now = matchingFiles()
        let fresh = now.subtracting(known)
        known = now
        // Let the file finish writing before reading it.
        for name in fresh {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.ingest(name) }
        }
    }

    private func ingest(_ name: String) {
        let url = dirURL.appendingPathComponent(name)
        guard let raw = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: raw) else { return }
        let png = rep.representation(using: .png, properties: [:]) ?? raw
        // Store the ORIGINAL file bytes (no re-encode) so the blob keeps full resolution, colour
        // profile and DPI — that blob is exactly what "Save to Photos" writes into the library.
        let draft = PasteboardDraft(
            kind: .image, text: nil, rtfData: nil, imagePNG: raw,
            imageWidth: rep.pixelsWide, imageHeight: rep.pixelsHigh,
            fileURLs: nil, urlString: nil, colorHex: nil,
            sourceBundleID: nil, sourceAppName: "Screenshot", hash: raw)
        store.ingest(draft)

        // ⌘⇧4 only writes a file — it never touches the clipboard. Put the screenshot on the
        // clipboard so a plain ⌘V pastes it immediately (no need to open BoardClip). Suppress the
        // monitor so it doesn't re-capture our own write as a duplicate.
        if settings.copyScreenshotsToClipboard {
            let pb = NSPasteboard.general
            pb.clearContents()
            let item = NSPasteboardItem()
            item.setData(png, forType: .png)
            if let tiff = rep.tiffRepresentation { item.setData(tiff, forType: .tiff) }
            pb.writeObjects([item])
            monitor.suppressedChangeCount = pb.changeCount
        }
    }
}
