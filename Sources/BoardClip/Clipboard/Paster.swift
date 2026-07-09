import AppKit
import ApplicationServices
import UniformTypeIdentifiers

/// Writes a clip back to the pasteboard and (optionally) pastes it into the previously focused app.
@MainActor
enum Paster {
    /// True if we're allowed to synthesize keystrokes (Accessibility permission granted).
    static var canAutoPaste: Bool { AXIsProcessTrusted() }

    /// Put `item` on the pasteboard. `monitor` (if given) is told to ignore the resulting change
    /// so we don't re-capture our own write.
    @discardableResult
    static func writeToPasteboard(_ item: ClipItem, asPlainText: Bool, monitor: ClipboardMonitor?) -> Bool {
        let pb = NSPasteboard.general

        if asPlainText {
            let text = item.bestPlainText
            guard !text.isEmpty else { return false }
            pb.clearContents()
            let wrote = pb.setString(text, forType: .string)
            if wrote { monitor?.suppressedChangeCount = pb.changeCount }
            return wrote
        }

        let wrote: Bool
        switch item.kind {
        case .text, .link:
            let text = item.text ?? item.urlString ?? ""
            guard !text.isEmpty else { return false }
            pb.clearContents()
            wrote = pb.setString(text, forType: .string)
        case .rtf:
            let text = item.text ?? ""
            guard item.rtfData != nil || !text.isEmpty else { return false }
            pb.clearContents()
            let wroteRTF = item.rtfData.map { pb.setData($0, forType: .rtf) } ?? false
            let wroteText = !text.isEmpty && pb.setString(text, forType: .string)
            wrote = wroteRTF || wroteText
        case .color:
            guard let hex = item.colorHex, let color = NSColor(hex: hex) else { return false }
            pb.clearContents()
            let wroteColor = pb.writeObjects([color])
            let wroteText = pb.setString(hex, forType: .string)
            wrote = wroteColor || wroteText
        case .image:
            guard let name = item.imageFileName,
                  let data = try? Data(contentsOf: AppPaths.blobURL(name)),
                  !data.isEmpty else { return false }
            pb.clearContents()
            wrote = pb.setData(data, forType: item.imagePasteboardType)
        case .file:
            let paths = item.fileURLs ?? []
            guard !paths.isEmpty,
                  paths.allSatisfy({ FileManager.default.fileExists(atPath: $0) }) else { return false }
            pb.clearContents()
            wrote = pb.writeObjects(paths.map { URL(fileURLWithPath: $0) as NSURL })
        }

        if wrote { monitor?.suppressedChangeCount = pb.changeCount }
        return wrote
    }

    /// Full flow: copy → reactivate the previous app → synthesize ⌘V.
    @discardableResult
    static func paste(_ item: ClipItem,
                      asPlainText: Bool,
                      previousApp: NSRunningApplication?,
                      monitor: ClipboardMonitor?,
                      store: HistoryStore,
                      onAutoPasteFailure: @escaping @MainActor @Sendable () -> Void = {}) -> Bool {
        guard writeToPasteboard(item, asPlainText: asPlainText, monitor: monitor) else {
            return false
        }
        store.markUsed(item)

        guard canAutoPaste else { return true } // fall back to manual ⌘V
        guard let previousApp else {
            NSLog("[BoardClip] Refusing to auto-paste because the destination app is unknown")
            DispatchQueue.main.async(execute: onAutoPasteFailure)
            return true
        }

        // Hand activation back to the app that was focused, then paste once it's actually frontmost.
        previousApp.activate()
        waitUntilFrontmost(previousApp, tries: 0, onFailure: onAutoPasteFailure)
        return true
    }

    /// App reactivation is asynchronous, so poll (≤~300ms) until the target app is frontmost before
    /// synthesizing ⌘V — otherwise the keystroke can land on BoardClip or arrive before the switch.
    private static func waitUntilFrontmost(_ app: NSRunningApplication,
                                           tries: Int,
                                           onFailure: @escaping @MainActor @Sendable () -> Void) {
        let front = NSWorkspace.shared.frontmostApplication
        let ready = front?.processIdentifier == app.processIdentifier
        if ready {
            sendCommandV()
        } else if tries >= 12 {
            NSLog("[BoardClip] Refusing to paste because the destination app did not become frontmost")
            NSSound.beep()
            onFailure()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) {
                waitUntilFrontmost(app, tries: tries + 1, onFailure: onFailure)
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
        case .image: return text ?? imageText
        }
    }

    var imagePasteboardType: NSPasteboard.PasteboardType {
        if imageUTTypeIdentifier == UTType.jpeg.identifier
            || imageFileName?.lowercased().hasSuffix(".jpg") == true
            || imageFileName?.lowercased().hasSuffix(".jpeg") == true {
            return NSPasteboard.PasteboardType(UTType.jpeg.identifier)
        }
        return .png
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
