import AppKit
import ApplicationServices

/// Writes a clip back to the pasteboard and (optionally) pastes it into the previously focused app.
@MainActor
enum Paster {
    /// True if we're allowed to synthesize keystrokes (Accessibility permission granted).
    static var canAutoPaste: Bool { AXIsProcessTrusted() }

    /// Put `item` on the pasteboard. `monitor` (if given) is told to ignore the resulting change
    /// so we don't re-capture our own write.
    static func writeToPasteboard(_ item: ClipItem, asPlainText: Bool, monitor: ClipboardMonitor?) {
        let pb = NSPasteboard.general
        pb.clearContents()

        if asPlainText {
            pb.setString(item.bestPlainText, forType: .string)
        } else {
            switch item.kind {
            case .text, .link:
                pb.setString(item.text ?? item.urlString ?? "", forType: .string)
            case .rtf:
                if let rtf = item.rtfData { pb.setData(rtf, forType: .rtf) }
                pb.setString(item.text ?? "", forType: .string)
            case .color:
                if let hex = item.colorHex, let color = NSColor(hex: hex) {
                    pb.writeObjects([color])
                }
                pb.setString(item.colorHex ?? "", forType: .string)
            case .image:
                if let name = item.imageFileName,
                   let data = try? Data(contentsOf: AppPaths.blobURL(name)) {
                    pb.setData(data, forType: .png)
                }
            case .file:
                let urls = (item.fileURLs ?? []).map { URL(fileURLWithPath: $0) as NSURL }
                if !urls.isEmpty { pb.writeObjects(urls) }
            }
        }

        monitor?.suppressedChangeCount = pb.changeCount
    }

    /// Full flow: copy → reactivate the previous app → synthesize ⌘V.
    static func paste(_ item: ClipItem,
                      asPlainText: Bool,
                      previousApp: NSRunningApplication?,
                      monitor: ClipboardMonitor?,
                      store: HistoryStore) {
        writeToPasteboard(item, asPlainText: asPlainText, monitor: monitor)
        store.markUsed(item)

        guard canAutoPaste else { return } // fall back to manual ⌘V

        // Hand activation back to the app that was focused, then paste once it's actually frontmost.
        previousApp?.activate()
        waitUntilFrontmost(previousApp, tries: 0)
    }

    /// App reactivation is asynchronous, so poll (≤~300ms) until the target app is frontmost before
    /// synthesizing ⌘V — otherwise the keystroke can land on BoardClip or arrive before the switch.
    private static func waitUntilFrontmost(_ app: NSRunningApplication?, tries: Int) {
        let ourPID = NSRunningApplication.current.processIdentifier
        let front = NSWorkspace.shared.frontmostApplication
        let ready: Bool
        if let app {
            ready = front?.processIdentifier == app.processIdentifier
        } else {
            ready = front?.processIdentifier != ourPID // anything but us
        }
        if ready || tries >= 12 {
            sendCommandV()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) {
                waitUntilFrontmost(app, tries: tries + 1)
            }
        }
    }

    /// Synthesize a ⌘V key press into the frontmost app.
    static func sendCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9 // 'v'
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        let loc: CGEventTapLocation = .cgAnnotatedSessionEventTap
        down?.post(tap: loc)
        up?.post(tap: loc)
    }
}

extension ClipItem {
    var bestPlainText: String {
        switch kind {
        case .text, .rtf: return text ?? ""
        case .link: return urlString ?? text ?? ""
        case .color: return colorHex ?? ""
        case .file: return (fileURLs ?? []).joined(separator: "\n")
        case .image: return text ?? ""
        }
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard let v = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: CGFloat
        switch s.count {
        case 6:
            r = CGFloat((v & 0xFF0000) >> 16) / 255
            g = CGFloat((v & 0x00FF00) >> 8) / 255
            b = CGFloat(v & 0x0000FF) / 255
            a = 1
        case 8:
            r = CGFloat((v & 0xFF000000) >> 24) / 255
            g = CGFloat((v & 0x00FF0000) >> 16) / 255
            b = CGFloat((v & 0x0000FF00) >> 8) / 255
            a = CGFloat(v & 0x000000FF) / 255
        default:
            return nil
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }
}
